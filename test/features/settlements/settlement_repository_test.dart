import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/features/settlements/domain/settlement_repository.dart';

void main() {
  group('SettlementRepositoryImpl', () {
    late AppDatabase db;
    late SettlementRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = SettlementRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    // Seeds a trip where [toMemberId] overpaid and is owed [debt] by
    // [fromMemberId]: a single expense split across the two, paid by one.
    Future<(int tripId, int payerId, int otherId)> seedDebt({
      int amountMinor = 50_00,
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

    test(
      'recordPayment creates a settlement and accumulates partial payments',
      () async {
        final (tripId, payerId, otherId) = await seedDebt();

        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 25_00,
          paidMinor: 10_00,
        );
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 25_00,
          paidMinor: 15_00,
        );

        final rows = await db.settlementDao.getByTrip(tripId);
        expect(rows, hasLength(1));
        expect(rows.single.fromMemberId, otherId);
        expect(rows.single.toMemberId, payerId);
        expect(rows.single.amountMinor, 25_00);
        expect(rows.single.amountPaidMinor, 25_00);
        expect(rows.single.paidAt, isNotNull);
      },
    );

    test(
      'recordPayment refuses a payment above the outstanding debt',
      () async {
        final (tripId, payerId, otherId) = await seedDebt();

        expect(
          () => repository.recordPayment(
            tripId: tripId,
            fromMemberId: otherId,
            toMemberId: payerId,
            amountMinor: 25_00,
            paidMinor: 26_00,
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test(
      'recordPayment refuses self-settlement and non-positive amounts',
      () async {
        final (tripId, payerId, otherId) = await seedDebt();

        await expectLater(
          repository.recordPayment(
            tripId: tripId,
            fromMemberId: payerId,
            toMemberId: payerId,
            amountMinor: 1_00,
            paidMinor: 1_00,
          ),
          throwsA(isA<ValidationException>()),
        );
        await expectLater(
          repository.recordPayment(
            tripId: tripId,
            fromMemberId: otherId,
            toMemberId: payerId,
            amountMinor: 1_00,
            paidMinor: 0,
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('recordPayment rejects further payments once fully settled', () async {
      final (tripId, payerId, otherId) = await seedDebt();

      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 25_00,
        paidMinor: 25_00,
      );

      expect(
        () => repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 25_00,
          paidMinor: 1_00,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('deleteById removes a settlement', () async {
      final (tripId, payerId, otherId) = await seedDebt();
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 10_00,
        paidMinor: 10_00,
      );
      final row = (await db.settlementDao.getByTrip(tripId)).single;

      await repository.deleteById(row.id);

      expect(await db.settlementDao.getByTrip(tripId), isEmpty);
    });

    test(
      'rebase keeps amountPaidMinor within amountMinor when the debt grows',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 50_00);

        // Ben owes Ana 25.00; record a 10.00 partial payment.
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 25_00,
          paidMinor: 10_00,
        );

        // A second dinner adds another 25.00 debt for Ben.
        await ExpenseRepositoryImpl(db).createExpense(
          tripId: tripId,
          description: 'Dinner 2',
          amountMinor: 50_00,
          payerMemberId: payerId,
          participantMemberIds: [payerId, otherId],
        );

        // Ben now owes 40.00 outstanding; paying 35.00 on top of the existing
        // 10.00 keeeps the running row internally consistent.
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 40_00,
          paidMinor: 35_00,
        );

        final row = (await db.settlementDao.getByTrip(tripId)).single;
        expect(row.amountMinor, 50_00);
        expect(row.amountPaidMinor, 45_00);
        expect(row.amountPaidMinor, lessThanOrEqualTo(row.amountMinor));
      },
    );

    test(
      'partial payments accumulate across installments (1035 => 1000 + 35)',
      () async {
        // Expense of 2070 split two ways leaves an outstanding debt of 1035.
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 2070_00);

        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 1035_00,
          paidMinor: 1000_00,
        );
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 1035_00,
          paidMinor: 35_00,
        );

        final rows = await db.settlementDao.getByTrip(tripId);
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row.amountMinor, 1035_00);
        expect(row.amountPaidMinor, 1035_00);
        expect(row.paidAt, isNotNull);
      },
    );

    test(
      'setPaidAmount adjusts partial amounts and stamps paidAt when paid',
      () async {
        final (tripId, payerId, otherId) = await seedDebt(amountMinor: 50_00);
        await repository.recordPayment(
          tripId: tripId,
          fromMemberId: otherId,
          toMemberId: payerId,
          amountMinor: 25_00,
          paidMinor: 10_00,
        );
        final id = (await db.settlementDao.getByTrip(tripId)).single.id;

        await repository.setPaidAmount(settlementId: id, paidMinor: 25_00);
        final paid = (await db.settlementDao.getById(id))!;
        expect(paid.amountPaidMinor, 25_00);
        expect(paid.paidAt, isNotNull);
      },
    );

    test('setPaidAmount to zero marks the settlement unpaid', () async {
      final (tripId, payerId, otherId) = await seedDebt(amountMinor: 50_00);
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 25_00,
        paidMinor: 25_00,
      );
      final id = (await db.settlementDao.getByTrip(tripId)).single.id;

      await repository.setPaidAmount(settlementId: id, paidMinor: 0);
      final row = (await db.settlementDao.getById(id))!;
      expect(row.amountPaidMinor, 0);
      expect(row.paidAt, isNull);
    });

    test('setPaidAmount rejects a negative amount', () async {
      final (tripId, payerId, otherId) = await seedDebt(amountMinor: 50_00);
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 25_00,
        paidMinor: 10_00,
      );
      final id = (await db.settlementDao.getByTrip(tripId)).single.id;

      await expectLater(
        repository.setPaidAmount(settlementId: id, paidMinor: -1),
        throwsA(isA<ValidationException>()),
      );
    });

    test('setPaidAmount rejects an amount above the obligation', () async {
      final (tripId, payerId, otherId) = await seedDebt(amountMinor: 50_00);
      await repository.recordPayment(
        tripId: tripId,
        fromMemberId: otherId,
        toMemberId: payerId,
        amountMinor: 25_00,
        paidMinor: 10_00,
      );
      final id = (await db.settlementDao.getByTrip(tripId)).single.id;

      await expectLater(
        repository.setPaidAmount(settlementId: id, paidMinor: 26_00),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
