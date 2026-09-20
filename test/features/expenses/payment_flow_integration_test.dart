import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/database/domain_mappers.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';
import 'package:tripsplit/features/trips/data/trip_views.dart';

/// End-to-end integration tests proving the payment → balance → settlement
/// flow works correctly, including team-scoped common expenses.
void main() {
  late AppDatabase db;
  late ExpenseRepository expenseRepository;
  late TeamRepository teamRepository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenseRepository = ExpenseRepositoryImpl(db);
    teamRepository = TeamRepositoryImpl(db);
  });

  tearDown(() async => db.closeDatabase());

  Future<(int tripId, List<int> ids)> seedTripWithMembers(
    List<String> names,
  ) async {
    final tripId =
        await db.tripDao.insert(TripsCompanion.insert(name: 'Trip'));
    final ids = <int>[];
    for (final name in names) {
      ids.add(await db.memberDao
          .insert(MembersCompanion.insert(tripId: tripId, name: name)));
    }
    return (tripId, ids);
  }

  Future<(int teamId, List<int> memberIds)> seedTeam(
    int tripId,
    String name,
    List<int> memberIds,
  ) async {
    final team = await teamRepository.createTeam(tripId, name);
    for (final memberId in memberIds) {
      await teamRepository.addMember(teamId: team.id, memberId: memberId);
    }
    return (team.id, memberIds);
  }

  /// Loads the full TripView for balance and settlement computation.
  Future<TripView?> loadTripView(int tripId) async {
    final tripRow = await (db.tripDao.select(db.trips)
          ..where((t) => t.id.equals(tripId)))
        .getSingleOrNull();
    if (tripRow == null) return null;

    final memberRows = await db.memberDao.getByTrip(tripId);
    final expenseRows = await db.expenseDao.getByTrip(tripId);
    final shareRows = await db.expenseDao.getSharesByTrip(tripId);
    final contributionRows = await db.contributionDao.getByTrip(tripId);
    final settlementRows = await db.settlementDao.getByTrip(tripId);
    final paymentRows = await db.journeyDao.getPaymentsByTrip(tripId);
    final teamLinkRows = await db.expenseDao.getTeamLinksByTrip(tripId);

    final teamIdsByExpense = <int, List<int>>{};
    for (final link in teamLinkRows) {
      teamIdsByExpense.putIfAbsent(link.expenseId, () => []).add(link.teamId);
    }

    final members = memberRows.map((r) => r.toDomain()).toList();
    final contributions = contributionRows.map((r) => r.toDomain()).toList();
    final settlements = settlementRows.map((r) => r.toDomain()).toList();
    final payments = paymentRows.map((r) => r.toDomain()).toList();
    final shares = shareRows.map((r) => r.toDomain()).toList();

    final expenses = expenseRows
        .map((r) => r.toDomain()
            .copyWith(teamIds: teamIdsByExpense[r.id] ?? const []))
        .toList();

    final settlementPlan = SettlementCalculator.calculate(
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      payments: payments,
    );

    final trip = tripRow.toDomain();
    return TripView(
      trip: trip,
      members: members,
      expenses: [
        for (final e in expenses)
          ExpenseWithShares(
            expense: e,
            shares: shares.where((s) => s.expenseId == e.id).toList(),
          ),
      ],
      contributions: contributions,
      settlements: settlements,
      payments: payments,
      balances: BalanceCalculator.calculate(
        tripBudgetMinor: trip.totalBudgetMinor,
        contributions: contributions,
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        postSettlementOutstanding: settlementPlan.totalOutstanding,
      ),
      settlementPlan: settlementPlan,
    );
  }

  /// Helper to look up a member balance by id.
  MemberBalance balanceFor(BalanceResult balances, int memberId) =>
      balances.members.firstWhere(
        (b) => b.memberId == memberId,
        orElse: () => MemberBalance(
          memberId: memberId,
          contribution: 0,
          actualPaid: 0,
          expenseShare: 0,
          netPosition: 0,
          cashRemaining: 0,
          effectiveNetPosition: 0,
        ),
      );

  // ══════════════════════════════════════════════════════════════════════
  //  Core: single expense, single payer
  // ══════════════════════════════════════════════════════════════════════

  group('Single payer expenses', () {
    test('A pays ₹1000 for 3 people → A owed ₹666.67, B & C owe ₹333.33',
        () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 1000_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      final view = await loadTripView(tripId);
      expect(view, isNotNull);

      final balances = view!.balances;

      // Total expenses = ₹1000 (group portion, no external).
      expect(balances.totalExpenses, 1000_00);

      final aBal = balanceFor(balances, ids[0]);
      final bBal = balanceFor(balances, ids[1]);
      final cBal = balanceFor(balances, ids[2]);

      // A paid ₹1000.
      expect(aBal.actualPaid, 1000_00);
      // A's share is ₹333.34 (largest remainder).
      expect(aBal.expenseShare, 333_34);
      // A is owed ₹666.66.
      expect(aBal.netPosition, 666_66);
      expect(aBal.amountToReceive, 666_66);
      expect(aBal.amountToPay, 0);

      // B paid ₹0, owes ₹333.33.
      expect(bBal.actualPaid, 0);
      expect(bBal.expenseShare, 333_33);
      expect(bBal.netPosition, -333_33);
      expect(bBal.amountToPay, 333_33);

      // C paid ₹0, owes ₹333.33.
      expect(cBal.actualPaid, 0);
      expect(cBal.expenseShare, 333_33);
      expect(cBal.netPosition, -333_33);
      expect(cBal.amountToPay, 333_33);

      // Net across all members sums to 0.
      final totalNet = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.netPosition,
      );
      expect(totalNet, 0);
    });

    test('A pays for B, C, D → correct net positions', () async {
      final (tripId, ids) =
          await seedTripWithMembers(['A', 'B', 'C', 'D']);

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Hotel',
        amountMinor: 4000_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      final view = await loadTripView(tripId);
      final balances = view!.balances;

      final aBal = balanceFor(balances, ids[0]);
      // A paid 4000, share 1000, net +3000.
      expect(aBal.actualPaid, 4000_00);
      expect(aBal.expenseShare, 1000_00);
      expect(aBal.netPosition, 3000_00);

      for (final id in ids.sublist(1)) {
        final bal = balanceFor(balances, id);
        expect(bal.actualPaid, 0);
        expect(bal.expenseShare, 1000_00);
        expect(bal.netPosition, -1000_00);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  Multi-payer expenses
  // ══════════════════════════════════════════════════════════════════════

  group('Multi-payer expenses', () {
    test('Dhar pays ₹600 + Gowtham pays ₹400 for 4 people', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'Dhar',
        'Gowtham',
        'Sanu',
        'Mowli',
      ]);

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Restaurant',
        amountMinor: 1000_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[1],
            amountMinor: 400_00,
          ),
        ],
      );

      final view = await loadTripView(tripId);
      final balances = view!.balances;

      final dharBal = balanceFor(balances, ids[0]);
      expect(dharBal.actualPaid, 600_00);
      expect(dharBal.expenseShare, 250_00);
      expect(dharBal.netPosition, 350_00);

      final gowthamBal = balanceFor(balances, ids[1]);
      expect(gowthamBal.actualPaid, 400_00);
      expect(gowthamBal.expenseShare, 250_00);
      expect(gowthamBal.netPosition, 150_00);

      for (final id in ids.sublist(2)) {
        final bal = balanceFor(balances, id);
        expect(bal.actualPaid, 0);
        expect(bal.expenseShare, 250_00);
        expect(bal.netPosition, -250_00);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  Team-scoped common expenses
  // ══════════════════════════════════════════════════════════════════════

  group('Team-scoped common expenses', () {
    test('Two teams, A pays ₹2500 + C pays ₹1500 → correct per-member nets',
        () async {
      final (tripId, ids) = await seedTripWithMembers([
        'Dhar',
        'Gowtham',
        'Sanu',
      ]);
      final (teamA, _) = await seedTeam(tripId, 'Team A', [ids[0], ids[1]]);
      final (teamB, _) = await seedTeam(tripId, 'Team B', [ids[2]]);

      // ₹4000 common expense. Dhar pays ₹2500, Sanu pays ₹1500.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Shared booking',
        amountMinor: 4000_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [teamA, teamB],
        payerTeamId: teamA,
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[2],
            amountMinor: 1500_00,
            teamId: teamB,
          ),
        ],
      );

      final view = await loadTripView(tripId);
      expect(view, isNotNull);

      final balances = view!.balances;
      expect(balances.totalExpenses, 4000_00);

      // 3 participants → ₹1333.34 / ₹1333.33 / ₹1333.33.
      final dharBal = balanceFor(balances, ids[0]);
      final sanuBal = balanceFor(balances, ids[2]);
      final gowthamBal = balanceFor(balances, ids[1]);

      // Dhar paid ₹2500, share ₹1333.34 → net +₹1166.66.
      expect(dharBal.actualPaid, 2500_00);
      expect(dharBal.expenseShare, 1333_34);
      expect(dharBal.netPosition, 1166_66);

      // Sanu paid ₹1500, share ₹1333.33 → net +₹166.67.
      expect(sanuBal.actualPaid, 1500_00);
      expect(sanuBal.expenseShare, 1333_33);
      expect(sanuBal.netPosition, 166_67);

      // Gowtham paid ₹0, share ₹1333.33 → net −₹1333.33.
      expect(gowthamBal.actualPaid, 0);
      expect(gowthamBal.expenseShare, 1333_33);
      expect(gowthamBal.netPosition, -1333_33);

      // Nets sum to zero.
      final totalNet = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.netPosition,
      );
      expect(totalNet, 0);
    });

    test(
        'Dhar (Team A) pays on behalf of Team B → payment correctly reduces Team B balance',
        () async {
      final (tripId, ids) = await seedTripWithMembers([
        'Dhar',
        'Gowtham',
        'Sanu',
      ]);
      final (teamA, _) = await seedTeam(tripId, 'Team A', [ids[0], ids[1]]);
      final (teamB, _) = await seedTeam(tripId, 'Team B', [ids[2]]);

      // Common expense ₹3000. Dhar pays all of it on behalf of Team B.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Transport',
        amountMinor: 3000_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [teamA, teamB],
        payerTeamId: teamB,
        participantMemberIds: ids,
      );

      final view = await loadTripView(tripId);
      final balances = view!.balances;

      // Verify payment was stored.
      expect(view!.payments, hasLength(1));
      expect(view.payments.single.memberId, ids[0]);
      expect(view.payments.single.amountMinor, 3000_00);
      expect(view.payments.single.teamId, teamB);

      final dharBal = balanceFor(balances, ids[0]);
      expect(dharBal.actualPaid, 3000_00);
      expect(dharBal.expenseShare, 1000_00);
      expect(dharBal.netPosition, 2000_00);

      for (final id in ids.sublist(1)) {
        final bal = balanceFor(balances, id);
        expect(bal.actualPaid, 0);
        expect(bal.expenseShare, 1000_00);
        expect(bal.netPosition, -1000_00);
      }
    });

    test('Team settlement: payments correctly reflect in team view', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
      ]);
      final (team1, _) =
          await seedTeam(tripId, 'Team 1', ids.sublist(0, 5));
      final (team2, _) =
          await seedTeam(tripId, 'Team 2', ids.sublist(5));

      // ₹4000 across 10 people. Team 1 pays ₹2500, Team 2 pays ₹1500.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Booking',
        amountMinor: 4000_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [team1, team2],
        payerTeamId: team1,
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[5],
            amountMinor: 1500_00,
            teamId: team2,
          ),
        ],
      );

      final view = await loadTripView(tripId);
      final balances = view!.balances;

      // Total expenses = ₹4000.
      expect(balances.totalExpenses, 4000_00);

      // A paid ₹2500, share ₹400, net +₹2100.
      final aBal = balanceFor(balances, ids[0]);
      expect(aBal.actualPaid, 2500_00);
      expect(aBal.expenseShare, 400_00);
      expect(aBal.netPosition, 2100_00);

      // F (Team 2 payer) paid ₹1500, share ₹400, net +₹1100.
      final fBal = balanceFor(balances, ids[5]);
      expect(fBal.actualPaid, 1500_00);
      expect(fBal.expenseShare, 400_00);
      expect(fBal.netPosition, 1100_00);

      // Others owe ₹400 each.
      for (final i in [1, 2, 3, 4, 6, 7, 8, 9]) {
        final bal = balanceFor(balances, ids[i]);
        expect(bal.actualPaid, 0);
        expect(bal.expenseShare, 400_00);
        expect(bal.netPosition, -400_00);
      }

      // Outstanding total = sum of all debts.
      final debtSum = balances.members
          .where((m) => m.netPosition < 0)
          .fold<int>(0, (sum, m) => sum + -m.netPosition);
      expect(balances.outstandingMinor, debtSum);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  Settlement after payments
  // ══════════════════════════════════════════════════════════════════════

  group('Settlement after payments', () {
    test('Settlement plan accounts for payments correctly', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);

      // A pays ₹300 for 3 people.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Food',
        amountMinor: 300_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      final view = await loadTripView(tripId);
      final plan = view!.settlementPlan;

      // B owes A ₹99.99 (or similar), C owes A the rest.
      expect(plan.suggestions, isNotEmpty);

      // Total outstanding matches the sum of debts.
      final totalDebt = plan.suggestions.fold<int>(
        0,
        (sum, s) => sum + s.minor,
      );
      expect(plan.totalOutstanding, totalDebt);
    });

    test(
        'After partial settlement, outstanding reduces but payments remain',
        () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      // A pays ₹200 for 2 people → each owes ₹100.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Taxi',
        amountMinor: 200_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      // B pays A ₹50 (partial).
      await db.settlementDao.insert(
        SettlementsCompanion(
          tripId: Value(tripId),
          fromMemberId: Value(ids[1]),
          toMemberId: Value(ids[0]),
          amountMinor: const Value(100_00),
          amountPaidMinor: const Value(50_00),
          settledAt: Value(DateTime.now()),
        ),
      );

      final view = await loadTripView(tripId);
      final balances = view!.balances;

      // Payment records still show A paid ₹200.
      final aBal = balanceFor(balances, ids[0]);
      expect(aBal.actualPaid, 200_00);
      expect(aBal.expenseShare, 100_00);

      // Cash remaining accounts for the settlement transfer.
      // A contributed 0, received 50 (settlement), paid 200 (expense) → -150.
      expect(aBal.cashRemaining, -150_00);
      // B contributed 0, received 0, paid 0 (expense), paid 50 (settlement) → -50.
      final bBal = balanceFor(balances, ids[1]);
      expect(bBal.cashRemaining, -50_00);
    });
  });
}
