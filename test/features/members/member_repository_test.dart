import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/members/data/member_repository_impl.dart';
import 'package:tripsplit/features/members/domain/member.dart';
import 'package:tripsplit/features/members/domain/member_repository.dart';

void main() {
  group('MemberRepositoryImpl', () {
    late AppDatabase db;
    late MemberRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = MemberRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<int> seedTrip(String name) =>
        db.tripDao.insert(TripsCompanion.insert(name: name));

    test('save returns the persisted member with its assigned id', () async {
      final tripId = await seedTrip('Rome');

      final saved = await repository.save(
        Member(id: 0, tripId: tripId, name: ' Ana ', createdAt: DateTime.now()),
      );

      expect(saved.id, greaterThan(0));
      expect(saved.name, 'Ana');

      final loaded = await repository.findById(saved.id);
      expect(loaded, isNotNull);
      expect(loaded!.tripId, tripId);
      expect(loaded.name, 'Ana');
    });

    test('save rejects a duplicate name inside the same trip', () async {
      final tripId = await seedTrip('Rome');
      await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );

      expect(
        () => repository.save(
          Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('save rejects renaming onto an existing name in the trip', () async {
      final tripId = await seedTrip('Rome');
      final ana = await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );
      await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ben', createdAt: DateTime.now()),
      );

      await expectLater(
        repository.save(ana.copyWith(name: 'Ben')),
        throwsA(isA<ValidationException>()),
      );

      // The rename did not silently corrupt anything.
      final renamed = await repository.findById(ana.id);
      expect(renamed!.name, 'Ana');
    });

    test('save allows the same name in a different trip', () async {
      final first = await seedTrip('Rome');
      final second = await seedTrip('Berlin');
      await repository.save(
        Member(id: 0, tripId: first, name: 'Ana', createdAt: DateTime.now()),
      );

      final saved = await repository.save(
        Member(id: 0, tripId: second, name: 'Ana', createdAt: DateTime.now()),
      );

      expect(saved.id, greaterThan(0));
    });

    test('save trims whitespace when updating', () async {
      final tripId = await seedTrip('Rome');
      final saved = await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );

      final updated = await repository.save(
        saved.copyWith(name: '  Ana Maria '),
      );
      expect(updated.name, 'Ana Maria');
    });

    test('deleteById removes a member with no activity', () async {
      final tripId = await seedTrip('Rome');
      final saved = await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );

      await repository.deleteById(saved.id);

      expect(await repository.findById(saved.id), isNull);
    });

    test('deleteById is blocked when the member is a payer', () async {
      final tripId = await seedTrip('Rome');
      final saved = await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );
      final expenses = ExpenseRepositoryImpl(db);
      await expenses.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 10_00,
        payerMemberId: saved.id,
        participantMemberIds: [saved.id],
      );

      expect(
        () => repository.deleteById(saved.id),
        throwsA(isA<ValidationException>()),
      );
      expect(await repository.findById(saved.id), isNotNull);
    });

    test('deleteById is allowed when the member only contributed', () async {
      final tripId = await seedTrip('Rome');
      final saved = await repository.save(
        Member(id: 0, tripId: tripId, name: 'Ana', createdAt: DateTime.now()),
      );
      await db.contributionDao.insert(
        ContributionsCompanion.insert(
          tripId: tripId,
          memberId: saved.id,
          amountMinor: const Value(10_00),
          createdAt: Value(DateTime.now()),
        ),
      );

      await repository.deleteById(saved.id);

      expect(await repository.findById(saved.id), isNull);
    });
  });
}
