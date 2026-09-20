import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';

void main() {
  group('ExpenseRepositoryImpl', () {
    late AppDatabase db;
    late ExpenseRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = ExpenseRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<int> seedTrip(List<String> members) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Rome'),
      );
      final ids = <int>[];
      for (final name in members) {
        ids.add(
          await db.memberDao.insert(
            MembersCompanion.insert(tripId: tripId, name: name),
          ),
        );
      }
      return tripId;
    }

    test('createExpense persists the expense and exact-sum shares', () async {
      final tripId = await seedTrip(['Ana', 'Ben', 'Cid']);
      final payer = (await db.memberDao.getByTrip(tripId))[0];

      await repository.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 100_00,
        payerMemberId: payer.id,
        participantMemberIds: (await db.memberDao.getByTrip(
          tripId,
        )).map((m) => m.id).toList(),
      );

      final expenses = await repository.getByTrip(tripId);
      expect(expenses, hasLength(1));
      expect(expenses.single.amountMinor, 100_00);

      final shares = await repository.getSharesFor(expenses.single.id);
      expect(shares, hasLength(3));
      final sum = shares.fold<int>(0, (acc, s) => acc + s.shareMinor);
      expect(sum, 100_00);
    });

    test(
      'updateExpense rewrites shares while preserving the exact total',
      () async {
        final tripId = await seedTrip(['Ana', 'Ben', 'Cid']);
        final members = await db.memberDao.getByTrip(tripId);

        await repository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: members.map((m) => m.id).toList(),
        );
        final expense = (await repository.getByTrip(tripId)).single;

        await repository.updateExpense(
          expenseId: expense.id,
          description: 'Lunch',
          amountMinor: 7_00,
          payerMemberId: members[1].id,
          participantMemberIds: [members[0].id, members[1].id],
        );

        final updated = (await repository.getByTrip(tripId)).single;
        expect(updated.description, 'Lunch');
        expect(updated.amountMinor, 7_00);
        expect(updated.payerMemberId, members[1].id);

        final shares = await repository.getSharesFor(updated.id);
        expect(shares, hasLength(2));
        expect(shares.fold<int>(0, (acc, s) => acc + s.shareMinor), 7_00);
      },
    );

    test('updateExpense throws when the expense does not exist', () async {
      final tripId = await seedTrip(['Ana']);
      final member = (await db.memberDao.getByTrip(tripId)).single;

      expect(
        () => repository.updateExpense(
          expenseId: 999,
          description: 'Ghost',
          amountMinor: 10_00,
          payerMemberId: member.id,
          participantMemberIds: [member.id],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('deleteExpense removes the expense and its shares', () async {
      final tripId = await seedTrip(['Ana', 'Ben']);
      final members = await db.memberDao.getByTrip(tripId);

      await repository.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 50_00,
        payerMemberId: members[0].id,
        participantMemberIds: members.map((m) => m.id).toList(),
      );
      final expense = (await repository.getByTrip(tripId)).single;

      await repository.deleteExpense(tripId: tripId, expenseId: expense.id);

      expect(await repository.getByTrip(tripId), isEmpty);
      expect(await repository.getSharesFor(expense.id), isEmpty);
    });

    test('createExpense rejects invalid input', () async {
      final tripId = await seedTrip(['Ana']);
      final member = (await db.memberDao.getByTrip(tripId)).single;

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Free ride',
          amountMinor: 0,
          payerMemberId: member.id,
          participantMemberIds: [member.id],
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'No one',
          amountMinor: 10_00,
          payerMemberId: member.id,
          participantMemberIds: const [],
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Outsider pays',
          amountMinor: 10_00,
          payerMemberId: 999,
          participantMemberIds: [member.id],
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Outsider joins',
          amountMinor: 10_00,
          payerMemberId: member.id,
          participantMemberIds: const [777],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'createExpense rejects an empty and an over-long description',
      () async {
        final tripId = await seedTrip(['Ana']);
        final member = (await db.memberDao.getByTrip(tripId)).single;

        await expectLater(
          repository.createExpense(
            tripId: tripId,
            description: '   ',
            amountMinor: 10_00,
            payerMemberId: member.id,
            participantMemberIds: [member.id],
          ),
          throwsA(isA<ValidationException>()),
        );

        await expectLater(
          repository.createExpense(
            tripId: tripId,
            description: 'x' * 201,
            amountMinor: 10_00,
            payerMemberId: member.id,
            participantMemberIds: [member.id],
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('createExpense rejects an invalid external portion', () async {
      final tripId = await seedTrip(['Ana']);
      final member = (await db.memberDao.getByTrip(tripId)).single;

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Negative external',
          amountMinor: 10_00,
          externalAmountMinor: -1,
          payerMemberId: member.id,
          participantMemberIds: [member.id],
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Fully external',
          amountMinor: 10_00,
          externalAmountMinor: 10_00,
          payerMemberId: member.id,
          participantMemberIds: [member.id],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('createExpense splits only the shareable amount with an external '
        'portion', () async {
      final tripId = await seedTrip(['Ana', 'Ben', 'Cid']);
      final members = await db.memberDao.getByTrip(tripId);

      await repository.createExpense(
        tripId: tripId,
        description: 'Registration',
        amountMinor: 730_90,
        externalAmountMinor: 365_50,
        payerMemberId: members[0].id,
        participantMemberIds: [members[0].id],
      );

      final expense = (await repository.getByTrip(tripId)).single;
      expect(expense.amountMinor, 730_90);
      expect(expense.externalAmountMinor, 365_50);

      final shares = await repository.getSharesFor(expense.id);
      // Group amount 36540 split to the payer as their own share.
      expect(shares, hasLength(1));
      expect(shares.single.memberId, members[0].id);
      expect(shares.single.shareMinor, 365_40);
      expect(shares.fold<int>(0, (acc, s) => acc + s.shareMinor), 365_40);
    });

    test(
      'custom shares must cover every participant and reject extras',
      () async {
        final tripId = await seedTrip(['Ana', 'Ben', 'Cid']);
        final members = await db.memberDao.getByTrip(tripId);

        await expectLater(
          repository.createExpense(
            tripId: tripId,
            description: 'Missing participant share',
            amountMinor: 100_00,
            payerMemberId: members[0].id,
            participantMemberIds: [members[0].id, members[1].id],
            scope: ExpenseScope.custom,
            customShares: {members[0].id: 50_00},
          ),
          throwsA(isA<ValidationException>()),
        );

        await expectLater(
          repository.createExpense(
            tripId: tripId,
            description: 'Share for a non-participant',
            amountMinor: 100_00,
            payerMemberId: members[0].id,
            participantMemberIds: [members[0].id, members[1].id],
            scope: ExpenseScope.custom,
            customShares: {
              members[0].id: 30_00,
              members[1].id: 60_00,
              members[2].id: 10_00,
            },
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('custom shares reject zero and negative amounts', () async {
      final tripId = await seedTrip(['Ana', 'Ben']);
      final members = await db.memberDao.getByTrip(tripId);

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Zero share',
          amountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: [members[0].id, members[1].id],
          scope: ExpenseScope.custom,
          customShares: {members[0].id: 100_00, members[1].id: 0},
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Negative share',
          amountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: [members[0].id, members[1].id],
          scope: ExpenseScope.custom,
          customShares: {members[0].id: 200_00, members[1].id: -100_00},
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('custom shares persist exactly as entered', () async {
      final tripId = await seedTrip(['Ana', 'Ben']);
      final members = await db.memberDao.getByTrip(tripId);

      await repository.createExpense(
        tripId: tripId,
        description: 'Custom meal',
        amountMinor: 100_00,
        payerMemberId: members[0].id,
        participantMemberIds: [members[0].id, members[1].id],
        scope: ExpenseScope.custom,
        customShares: {members[0].id: 40_00, members[1].id: 60_00},
      );

      final expense = (await repository.getByTrip(tripId)).single;
      final shares = await repository.getSharesFor(expense.id);
      expect(shares, hasLength(2));
      expect(shares.fold<int>(0, (acc, s) => acc + s.shareMinor), 100_00);
      expect(
        shares.firstWhere((s) => s.memberId == members[0].id).shareMinor,
        40_00,
      );
      expect(
        shares.firstWhere((s) => s.memberId == members[1].id).shareMinor,
        60_00,
      );
    });

    test('createExpense rejects duplicate participant ids', () async {
      final tripId = await seedTrip(['Ana', 'Ben']);
      final members = await db.memberDao.getByTrip(tripId);

      await expectLater(
        repository.createExpense(
          tripId: tripId,
          description: 'Twice listed',
          amountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: [members[0].id, members[0].id, members[1].id],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'updateExpense rewrites shares on the shareable group amount',
      () async {
        final tripId = await seedTrip(['Ana', 'Ben', 'Cid']);
        final members = await db.memberDao.getByTrip(tripId);

        await repository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: members.map((m) => m.id).toList(),
        );
        final expense = (await repository.getByTrip(tripId)).single;

        await repository.updateExpense(
          expenseId: expense.id,
          description: 'Lunch',
          amountMinor: 733_60,
          externalAmountMinor: 100_00,
          payerMemberId: members[0].id,
          participantMemberIds: [members[0].id, members[2].id],
        );

        final updated = (await repository.getByTrip(tripId)).single;
        expect(updated.description, 'Lunch');
        expect(updated.amountMinor, 733_60);
        expect(updated.externalAmountMinor, 100_00);

        final shares = await repository.getSharesFor(updated.id);
        expect(shares.fold<int>(0, (acc, s) => acc + s.shareMinor), 633_60);
        expect(shares, hasLength(2));
      },
    );

    test('transaction rolls back when a share insert fails', () async {
      final tripId = await seedTrip(['Ana']);
      final member = (await db.memberDao.getByTrip(tripId)).single;

      await expectLater(
        db.transaction(() async {
          final expenseId = await db.expenseDao.insert(
            ExpensesCompanion.insert(
              tripId: tripId,
              payerMemberId: member.id,
              description: 'Dinner',
              amountMinor: const Value(10_00),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
          await db.expenseDao.insertShare(
            ExpenseSharesCompanion.insert(
              expenseId: expenseId,
              memberId: 999,
              shareMinor: const Value(10_00),
            ),
          );
        }),
        throwsA(isA<SqliteException>()),
      );

      expect(await db.expenseDao.getByTrip(tripId), isEmpty);
    });
  });
}
