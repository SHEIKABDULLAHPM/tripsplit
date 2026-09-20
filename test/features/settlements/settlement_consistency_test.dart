import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/database/domain_mappers.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
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
}
