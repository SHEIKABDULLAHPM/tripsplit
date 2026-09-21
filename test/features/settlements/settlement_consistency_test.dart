import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/database/domain_mappers.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';
import 'package:tripsplit/features/settlements/domain/settlement_repository.dart';

void main() {
  group('Settlement live-consistency (one source of truth)', () {
    late AppDatabase db;
    late SettlementRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = SettlementRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    /// Seeds a trip with [amountMinor] split across Ana (payer) and Ben:
    /// Ben owes Ana half of it.
    Future<(int tripId, int payerId, int otherId)> seedDebt({
      int amountMinor = 100_00,
    }) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Rome'),
      );
      final payerId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      final otherId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ben'),
      );
      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: amountMinor,
        payerMemberId: payerId,
        participantMemberIds: [payerId, otherId],
      );
      return (tripId, payerId, otherId);
    }

    Future<void> addExpense(
      int tripId,
      int payerId,
      int otherId, {
      int amountMinor = 100_00,
    }) => ExpenseRepositoryImpl(db).createExpense(
      tripId: tripId,
      description: 'Dinner 2',
      amountMinor: amountMinor,
      payerMemberId: payerId,
      participantMemberIds: [payerId, otherId],
    );

    Future<SettlementResult> plan(int tripId) async {
      final expenses = (await db.expenseDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final shares = (await db.expenseDao.getSharesByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final settlements = (await db.settlementDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final payments = (await db.journeyDao.getPaymentsByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      return SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
    }

    Future<List<Settlement>> settlementsOf(int tripId) async =>
        (await db.settlementDao.getByTrip(
          tripId,
        )).map((row) => row.toDomain()).toList();

    test(
      'history remains in lockstep with the live plan after a new expense',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 100_00);
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 50_00,
          paidMinor: 30_00,
        );
        await addExpense(tripId, payerId, otherId);

        final rows = await db.settlementDao.getByTrip(tripId);
        final stored = rows.single;

        // The stored snapshot can be stale: obligation was recorded when the
        // pair owed 50.00, but expenses have since grown the true debt.
        expect(stored.amountMinor - stored.amountPaidMinor, 20_00);

        // The live plan is the source of truth every screen now derives from.
        final p = await plan(tripId);
        final liveRemaining = SettlementCalculator.outstandingBetween(
          p.suggestions,
          fromMemberId: otherId,
          toMemberId: payerId,
        );
        expect(liveRemaining, 70_00);
        expect(liveRemaining, p.totalOutstanding);

        final settlements = await settlementsOf(tripId);
        expect(
          SettlementCalculator.totalPaidBetween(
            settlements,
            fromMemberId: otherId,
            toMemberId: payerId,
          ),
          30_00,
        );
        expect(
          SettlementCalculator.liveObligationBetween(
            settlements,
            p.suggestions,
            fromMemberId: otherId,
            toMemberId: payerId,
          ),
          100_00,
        );
      },
    );

    test(
      'recording the live remaining self-heals the stored obligation',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 100_00);
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 50_00,
          paidMinor: 30_00,
        );
        await addExpense(tripId, payerId, otherId);

        // Live outstanding is now 70.00; pay it all off.
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 70_00,
          paidMinor: 70_00,
        );

        final p = await plan(tripId);
        expect(p.totalOutstanding, 0);

        final row = (await db.settlementDao.getByTrip(tripId)).single;
        expect(row.amountMinor, 100_00);
        expect(row.amountPaidMinor, 100_00);
        expect(row.paidAt, isNotNull);
      },
    );

    test(
      'deleting an expense shrinks the live remaining shown everywhere',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 100_00);
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 50_00,
          paidMinor: 30_00,
        );
        await addExpense(tripId, payerId, otherId);

        // Remove the second dinner entirely.
        final second = (await db.expenseDao.getByTrip(
          tripId,
        )).where((row) => row.description != 'Dinner').single;
        await ExpenseRepositoryImpl(
          db,
        ).deleteExpense(tripId: tripId, expenseId: second.id);

        final p = await plan(tripId);
        final liveRemaining = SettlementCalculator.outstandingBetween(
          p.suggestions,
          fromMemberId: otherId,
          toMemberId: payerId,
        );
        expect(liveRemaining, 20_00);
        expect(liveRemaining, p.totalOutstanding);
      },
    );

    test(
      'setPaidAmount accepts up to the live obligation and rebases',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 100_00);
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 50_00,
          paidMinor: 30_00,
        );
        await addExpense(tripId, payerId, otherId);

        // Live obligation is 100.00 (30 paid + 70 still owed), even though the
        // stored row snapshot is only 50.00.
        final rows = await db.settlementDao.getByTrip(tripId);
        final p = await plan(tripId);
        final obligation = SettlementCalculator.liveObligationBetween(
          await settlementsOf(tripId),
          p.suggestions,
          fromMemberId: otherId,
          toMemberId: payerId,
        );
        expect(obligation, 100_00);

        await repository.setPaidAmount(
          settlementId: rows.single.id,
          paidMinor: obligation,
        );
        final paidPath = (await db.settlementDao.getByTrip(tripId)).single;
        expect(paidPath.amountMinor, 100_00);
        expect(paidPath.amountPaidMinor, 100_00);
        expect(paidPath.paidAt, isNotNull);

        await expectLater(
          repository.setPaidAmount(
            settlementId: rows.single.id,
            paidMinor: obligation + 1,
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('marking unpaid restores the full live outstanding', () async {
      final (tripId, payerId, otherId) = await seedDebt(amountMinor: 100_00);
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 50_00,
        paidMinor: 30_00,
      );
      await addExpense(tripId, payerId, otherId);

      final id = (await db.settlementDao.getByTrip(tripId)).single.id;
      await repository.setPaidAmount(settlementId: id, paidMinor: 0);

      final p = await plan(tripId);
      expect(p.totalOutstanding, 100_00);
      final row = (await db.settlementDao.getById(id))!;
      expect(row.amountPaidMinor, 0);
      expect(row.paidAt, isNull);
    });
  });

  group('Team-aware record-payment consistency', () {
    late AppDatabase db;
    late SettlementRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = SettlementRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    /// Seeds the multi-payer, multi-team scenario used by the settlement
    /// planner: teams {Ana, Ben} and {Cal, Dia}; Ana (team 1) fronts 2500.00
    /// and Cal (team 2) fronts 1500.00 of a 4000.00 expense everyone shares
    /// equally (1000.00 each).
    Future<(int, int, int, int, int, int, int)> seedTeamTrip() async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Rome'),
      );
      final anaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      final benId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ben'),
      );
      final calId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Cal'),
      );
      final diaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Dia'),
      );
      final team1 = await db.journeyDao.insertTeam(
        TeamsCompanion.insert(tripId: tripId, name: 'Alpha'),
      );
      final team2 = await db.journeyDao.insertTeam(
        TeamsCompanion.insert(tripId: tripId, name: 'Beta'),
      );
      await db.journeyDao.addTeamMember(team1, anaId);
      await db.journeyDao.addTeamMember(team1, benId);
      await db.journeyDao.addTeamMember(team2, calId);
      await db.journeyDao.addTeamMember(team2, diaId);

      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Common',
        amountMinor: 4000_00,
        scope: ExpenseScope.team,
        payerMemberId: anaId,
        payerTeamId: team1,
        teamIds: [team1, team2],
        participantMemberIds: [anaId, benId, calId, diaId],
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: calId,
            amountMinor: 1500_00,
            teamId: team2,
          ),
        ],
      );

      return (tripId, anaId, benId, calId, diaId, team1, team2);
    }

    Future<SettlementResult> plan(int tripId) async {
      final expenses = (await db.expenseDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final shares = (await db.expenseDao.getSharesByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final settlements = (await db.settlementDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final payments = (await db.journeyDao.getPaymentsByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();
      final memberships = await db.journeyDao.getTeamMembersByTrip(tripId);
      final teamMemberIds = <int, Set<int>>{};
      for (final membership in memberships) {
        teamMemberIds
            .putIfAbsent(membership.teamId, () => {})
            .add(membership.memberId);
      }
      return SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        teamMemberIds: teamMemberIds.isNotEmpty ? teamMemberIds : null,
      );
    }

    test('recordPayment validates against the same team-aware plan the screens '
        'show, not an expense-derived map', () async {
      final (tripId, anaId, benId, _, _, _, _) = await seedTeamTrip();

      // What the record screen displays (real team_members map):
      // Ben owes Ana his full ₹1,000 share.
      final shown = await plan(tripId);
      final displayed = SettlementCalculator.outstandingBetween(
        shown.suggestions,
        fromMemberId: benId,
        toMemberId: anaId,
      );
      expect(displayed, 1000_00);

      // Paying ₹700 — safely inside the displayed ₹1,000 — must be
      // accepted. The old expense-derived map mis-links Ben to Ana's team
      // too and would report only ₹625, rejecting this valid payment.
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: benId,
        toMemberId: anaId,
        amountMinor: displayed,
        paidMinor: 700_00,
      );

      // Previous payments are deducted exactly once: the remaining ₹300
      // lands on the same row and keeps the original ₹1,000 obligation.
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: benId,
        toMemberId: anaId,
        amountMinor: 0,
        paidMinor: 300_00,
      );

      final after = await plan(tripId);
      expect(
        SettlementCalculator.outstandingBetween(
          after.suggestions,
          fromMemberId: benId,
          toMemberId: anaId,
        ),
        0,
      );
      // Only Ben's ₹1,000 edge is cleared; the rest of the group stays.
      expect(after.totalOutstanding, 1500_00);

      final row = (await db.settlementDao.getByTrip(
        tripId,
      )).where((r) => r.fromMemberId == benId && r.toMemberId == anaId).single;
      expect(row.amountMinor, 1000_00);
      expect(row.amountPaidMinor, 1000_00);
      expect(row.paidAt, isNotNull);

      // The stored cash matches the plan: nothing double-counted.
      expect(
        SettlementCalculator.totalPaidBetween(
          (await db.settlementDao.getByTrip(
            tripId,
          )).map((r) => r.toDomain()).toList(),
          fromMemberId: benId,
          toMemberId: anaId,
        ),
        1000_00,
      );
    });
  });
}
