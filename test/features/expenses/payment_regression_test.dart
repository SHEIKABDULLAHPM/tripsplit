import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/database/domain_mappers.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';

/// Comprehensive regression tests covering all 12 payment scenarios
/// from the requirements specification.
void main() {
  group('Payment regression tests', () {
    late AppDatabase db;
    late ExpenseRepository expenseRepository;
    late TeamRepository teamRepository;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenseRepository = ExpenseRepositoryImpl(db);
      teamRepository = TeamRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<(int tripId, List<int> ids)> seedTripWithMembers(
      List<String> names,
    ) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Trip'),
      );
      final ids = <int>[];
      for (final name in names) {
        ids.add(
          await db.memberDao.insert(
            MembersCompanion.insert(tripId: tripId, name: name),
          ),
        );
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

    /// Helper to load payments from the trip view stream.
    Future<List<ExpensePayment>> loadPayments(int tripId) async {
      final rows = await db.journeyDao.getPaymentsByTrip(tripId);
      return rows.map((r) => r.toDomain()).toList();
    }

    // ── Scenario 1: One member pays for himself ──────────────────────────

    test('Scenario 1: One member pays for himself', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);

      // A pays ₹300, split 3 ways (₹100 each).
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Lunch',
        amountMinor: 300_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      final payments = await loadPayments(tripId);
      expect(payments, hasLength(1));
      expect(payments.single.memberId, ids[0]);
      expect(payments.single.amountMinor, 300_00);

      final shares = await expenseRepository.getSharesFor(1);
      expect(shares, hasLength(3));
      for (final share in shares) {
        expect(share.shareMinor, 100_00);
      }

      // A paid 300, owes 100 → A is owed 200.
      final totalPaid = payments.fold<int>(0, (s, p) => s + p.amountMinor);
      expect(totalPaid, 300_00);
    });

    // ── Scenario 2: One member pays for another ──────────────────────────

    test('Scenario 2: One member pays for another', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      // A pays ₹200 on behalf of both A and B.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Taxi',
        amountMinor: 200_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      final payments = await loadPayments(tripId);
      expect(payments, hasLength(1));
      expect(payments.single.memberId, ids[0]);

      final shares = await expenseRepository.getSharesFor(1);
      // Each share is ₹100
      for (final share in shares) {
        expect(share.shareMinor, 100_00);
      }

      // A paid 200, owes 100 → net +100.
      // B paid 0, owes 100 → net -100.
    });

    // ── Scenario 3: One member pays for himself and multiple members ─────

    test(
      'Scenario 3: One member pays for himself and multiple members',
      () async {
        final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);

        // A pays ₹400, split 4 ways (₹100 each).
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 400_00,
          payerMemberId: ids[0],
          participantMemberIds: ids,
        );

        final payments = await loadPayments(tripId);
        expect(payments, hasLength(1));
        expect(payments.single.memberId, ids[0]);
        expect(payments.single.amountMinor, 400_00);

        final shares = await expenseRepository.getSharesFor(1);
        expect(shares, hasLength(4));
        for (final share in shares) {
          expect(share.shareMinor, 100_00);
        }
      },
    );

    // ── Scenario 4: One member pays for selected members from his team ──

    test(
      'Scenario 4: Cross-team payment — member pays on behalf of other team',
      () async {
        final (tripId, ids) = await seedTripWithMembers([
          'Dhar',
          'Gowtham',
          'Sanu',
        ]);
        final (teamA, _) = await seedTeam(tripId, 'Team A', [ids[0], ids[1]]);
        final (teamB, _) = await seedTeam(tripId, 'Team B', [ids[2]]);

        // Common expense across both teams. Dhar (Team A) pays ₹300 for all 3.
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Hotel',
          amountMinor: 300_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [teamA, teamB],
          payerTeamId: teamA,
          participantMemberIds: ids,
        );

        final expense = (await expenseRepository.getByTrip(tripId)).single;
        expect(expense.teamIds.toSet(), {teamA, teamB});

        final payments = await loadPayments(tripId);
        expect(payments, hasLength(1));
        expect(payments.single.memberId, ids[0]);
        expect(payments.single.amountMinor, 300_00);
        expect(payments.single.teamId, teamA);

        final shares = await expenseRepository.getSharesFor(expense.id);
        expect(shares, hasLength(3));
        for (final share in shares) {
          expect(share.shareMinor, 100_00);
        }
      },
    );

    // ── Scenario 5: One member pays for relevant members across teams ────

    test(
      'Scenario 5: Cross-team payment — payer from Team A pays for Team B',
      () async {
        final (tripId, ids) = await seedTripWithMembers([
          'Dhar',
          'Gowtham',
          'Sanu',
        ]);
        final (teamA, _) = await seedTeam(tripId, 'Team A', [ids[0], ids[1]]);
        final (teamB, _) = await seedTeam(tripId, 'Team B', [ids[2]]);

        // Dhar (Team A) pays for Team B's share. The payment is attributed to
        // Team B even though Dhar is not in Team B.
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Transport',
          amountMinor: 300_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [teamA, teamB],
          payerTeamId: teamB,
          participantMemberIds: ids,
        );

        final payments = await loadPayments(tripId);
        expect(payments, hasLength(1));
        expect(payments.single.memberId, ids[0]);
        expect(payments.single.teamId, teamB);

        // Dhar paid 300 for 3 participants → each owes 100.
        final shares = await expenseRepository.getSharesFor(1);
        expect(shares, hasLength(3));
      },
    );

    // ── Scenario 6: Multiple members pay the same common expense ─────────

    test('Scenario 6: Multiple members pay the same common expense', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'Dhar',
        'Gowtham',
        'Sanu',
        'Mowli',
      ]);

      // Dhar pays ₹600, Gowtham pays ₹400. Total ₹1000. 4 participants.
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

      final payments = await loadPayments(tripId);
      expect(payments, hasLength(2));

      final dharPay = payments.firstWhere((p) => p.memberId == ids[0]);
      expect(dharPay.amountMinor, 600_00);

      final gowthamPay = payments.firstWhere((p) => p.memberId == ids[1]);
      expect(gowthamPay.amountMinor, 400_00);

      final totalPaid = payments.fold<int>(0, (s, p) => s + p.amountMinor);
      expect(totalPaid, 1000_00);

      final shares = await expenseRepository.getSharesFor(1);
      expect(shares, hasLength(4));
      for (final share in shares) {
        expect(share.shareMinor, 250_00);
      }
    });

    // ── Scenario 7: Team-level combined with individual payment ──────────

    test(
      'Scenario 7: Team-level payment combined with individual payment',
      () async {
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
        final (team1, _) = await seedTeam(tripId, 'Team 1', ids.sublist(0, 5));
        final (team2, _) = await seedTeam(tripId, 'Team 2', ids.sublist(5));

        // ₹4000 across 10 members. Team 1 (A) pays ₹2500. Team 2 pays ₹1500.
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

        final payments = await loadPayments(tripId);
        expect(payments, hasLength(2));

        final aPayment = payments.firstWhere((p) => p.memberId == ids[0]);
        expect(aPayment.amountMinor, 2500_00);
        expect(aPayment.teamId, team1);

        final fPayment = payments.firstWhere((p) => p.memberId == ids[5]);
        expect(fPayment.amountMinor, 1500_00);
        expect(fPayment.teamId, team2);

        final totalPaid = payments.fold<int>(0, (s, p) => s + p.amountMinor);
        expect(totalPaid, 4000_00);

        final shares = await expenseRepository.getSharesFor(1);
        expect(shares, hasLength(10));
        for (final share in shares) {
          expect(share.shareMinor, 400_00);
        }

        // No double-counting: net across all members must be zero.
        final netByMember = <int, int>{};
        for (final p in payments) {
          netByMember[p.memberId] = p.amountMinor;
        }
        for (final s in shares) {
          netByMember[s.memberId] =
              (netByMember[s.memberId] ?? 0) - s.shareMinor;
        }
        final totalNet = netByMember.values.fold<int>(0, (s, v) => s + v);
        expect(totalNet, 0);
      },
    );

    // ── Scenario 8: Partial payment ──────────────────────────────────────

    test('Scenario 8: Partial payment via settlement', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      // A pays ₹200, split 2 ways (₹100 each).
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Taxi',
        amountMinor: 200_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      // Record a partial settlement: B pays A ₹50.
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

      final settlements = await db.settlementDao.getByTrip(tripId);
      expect(settlements, hasLength(1));
      expect(settlements.first.amountMinor, 100_00);
      expect(settlements.first.amountPaidMinor, 50_00);
    });

    // ── Scenario 9: Payment edited after creation ────────────────────────

    test('Scenario 9: Payment edited after creation', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);

      // Create: A pays ₹300, B pays ₹200. Total ₹500.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Hotel',
        amountMinor: 500_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[1],
            amountMinor: 200_00,
          ),
        ],
      );
      final expense = (await expenseRepository.getByTrip(tripId)).single;

      // Edit: A pays ₹400, C pays ₹100. Total still ₹500.
      await expenseRepository.updateExpense(
        expenseId: expense.id,
        description: 'Hotel',
        amountMinor: 500_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[2],
            amountMinor: 100_00,
          ),
        ],
      );

      final payments = await loadPayments(tripId);
      expect(payments, hasLength(2));

      final aPay = payments.firstWhere((p) => p.memberId == ids[0]);
      expect(aPay.amountMinor, 400_00);

      final cPay = payments.firstWhere((p) => p.memberId == ids[2]);
      expect(cPay.amountMinor, 100_00);

      final totalPaid = payments.fold<int>(0, (s, p) => s + p.amountMinor);
      expect(totalPaid, 500_00);

      // Shares remain the same (3 participants, equal split).
      final shares = await expenseRepository.getSharesFor(expense.id);
      expect(shares, hasLength(3));
    });

    // ── Scenario 10: Expense participants edited after payment ───────────

    test('Scenario 10: Participants edited after payment allocation', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);

      // Create with 4 participants. A pays ₹400.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Activities',
        amountMinor: 400_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );
      final expense = (await expenseRepository.getByTrip(tripId)).single;

      // Edit: Remove D from participants. Now 3 participants split ₹400.
      await expenseRepository.updateExpense(
        expenseId: expense.id,
        description: 'Activities',
        amountMinor: 400_00,
        payerMemberId: ids[0],
        participantMemberIds: [ids[0], ids[1], ids[2]],
      );

      final shares = await expenseRepository.getSharesFor(expense.id);
      expect(shares, hasLength(3));
      // D is no longer a participant.
      expect(shares.any((s) => s.memberId == ids[3]), isFalse);
    });

    // ── Scenario 11: Settlement created after payment allocation ─────────

    test('Scenario 11: Settlement after payment', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      // A pays ₹200, split 2 ways.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Food',
        amountMinor: 200_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
      );

      // Now record a settlement: B pays A ₹100 (the full obligation).
      await db.settlementDao.insert(
        SettlementsCompanion(
          tripId: Value(tripId),
          fromMemberId: Value(ids[1]),
          toMemberId: Value(ids[0]),
          amountMinor: const Value(100_00),
          amountPaidMinor: const Value(100_00),
          settledAt: Value(DateTime.now()),
          paidAt: Value(DateTime.now()),
        ),
      );

      final settlements = await db.settlementDao.getByTrip(tripId);
      expect(settlements, hasLength(1));
      expect(settlements.first.amountPaidMinor, 100_00);

      // Verify settlement plan reflects this.
      final allExpenses = await expenseRepository.getByTrip(tripId);
      final allShares = await expenseRepository.getSharesFor(
        allExpenses.single.id,
      );
      final allPayments = await loadPayments(tripId);
      final allSettlements = (await db.settlementDao.getByTrip(
        tripId,
      )).map((r) => r.toDomain()).toList();

      final plan = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: allSettlements.cast(),
        payments: allPayments,
      );

      // After the settlement, no more outstanding.
      expect(plan.totalOutstanding, 0);
    });

    // ── Scenario 12: Verify no amount is double-counted ──────────────────

    test(
      'Scenario 12: No double-counting across payments and shares',
      () async {
        final (tripId, ids) = await seedTripWithMembers([
          'A',
          'B',
          'C',
          'D',
          'E',
        ]);

        // Create two expenses.
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Expense 1',
          amountMinor: 500_00,
          payerMemberId: ids[0],
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: ids[1],
              amountMinor: 200_00,
            ),
          ],
        );

        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Expense 2',
          amountMinor: 300_00,
          payerMemberId: ids[2],
          participantMemberIds: ids,
        );

        // Load all payments and shares.
        final allExpenses = await expenseRepository.getByTrip(tripId);
        final allShares =
            await expenseRepository.getSharesFor(allExpenses[0].id)
              ..addAll(await expenseRepository.getSharesFor(allExpenses[1].id));
        final allPayments = await loadPayments(tripId);

        // Sum of all payments must equal sum of all expense amounts.
        final totalPaid = allPayments.fold<int>(0, (s, p) => s + p.amountMinor);
        final totalAmount = allExpenses.fold<int>(
          0,
          (s, e) => s + e.amountMinor,
        );
        expect(totalPaid, totalAmount);

        // Sum of all shares must equal sum of all group amounts.
        final totalShares = allShares.fold<int>(
          0,
          (s, sh) => s + sh.shareMinor,
        );
        final totalGroupAmount = allExpenses.fold<int>(
          0,
          (s, e) => s + (e.amountMinor - e.externalAmountMinor),
        );
        expect(totalShares, totalGroupAmount);

        // Net position across all members must be zero
        // (for equal split without external amounts).
        final netByMember = <int, int>{};
        for (final p in allPayments) {
          netByMember[p.memberId] =
              (netByMember[p.memberId] ?? 0) + p.amountMinor;
        }
        for (final s in allShares) {
          netByMember[s.memberId] =
              (netByMember[s.memberId] ?? 0) - s.shareMinor;
        }
        final totalNet = netByMember.values.fold<int>(0, (s, v) => s + v);
        expect(totalNet, 0);
      },
    );

    // ── Cross-team: common expense with multiple team payers ─────────────

    test(
      'Common expense across two teams: Dhar pays ₹2500, other pays ₹1500',
      () async {
        final (tripId, ids) = await seedTripWithMembers([
          'Dhar',
          'Gowtham',
          'Sanu',
        ]);
        final (teamA, _) = await seedTeam(tripId, 'Team A', [ids[0], ids[1]]);
        final (teamB, _) = await seedTeam(tripId, 'Team B', [ids[2]]);

        // Common expense: ₹4000. Dhar pays ₹2500, Sanu pays ₹1500.
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

        final payments = await loadPayments(tripId);
        final dharPay = payments.firstWhere((p) => p.memberId == ids[0]);
        expect(dharPay.amountMinor, 2500_00);

        final sanuPay = payments.firstWhere((p) => p.memberId == ids[2]);
        expect(sanuPay.amountMinor, 1500_00);

        final totalPaid = payments.fold<int>(0, (s, p) => s + p.amountMinor);
        expect(totalPaid, 4000_00);

        // 3 participants → each owes ₹1333.33 (or similar).
        final shares = await expenseRepository.getSharesFor(1);
        expect(shares, hasLength(3));
        final totalShares = shares.fold<int>(0, (s, sh) => s + sh.shareMinor);
        expect(totalShares, 4000_00);

        // Dhar net: paid 2500, owes ~1333 → positive.
        // Sanu net: paid 1500, owes ~1333 → positive.
        // Gowtham net: paid 0, owes ~1333 → negative.
        // Total net = 0.
        final netByMember = <int, int>{};
        for (final p in payments) {
          netByMember[p.memberId] = p.amountMinor;
        }
        for (final s in shares) {
          netByMember[s.memberId] =
              (netByMember[s.memberId] ?? 0) - s.shareMinor;
        }
        final totalNet = netByMember.values.fold<int>(0, (s, v) => s + v);
        expect(totalNet, 0);
      },
    );
  });
}
