import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/contributions/data/contribution_repository_impl.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/contributions/domain/contribution_repository.dart';

void main() {
  group('ContributionRepositoryImpl', () {
    late AppDatabase db;
    late ContributionRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = ContributionRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<int> seedMember() async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Goa'),
      );
      final memberId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Aya'),
      );
      return memberId;
    }

    test('creates a positive contribution', () async {
      final memberId = await seedMember();

      await repository.save(
        Contribution(
          id: 0,
          tripId: 1,
          memberId: memberId,
          amountMinor: 500_00,
          note: 'Pool',
          createdAt: DateTime.now(),
        ),
      );

      final loaded = await db.contributionDao.getByTrip(1);
      expect(loaded, hasLength(1));
      expect(loaded.single.amountMinor, 500_00);
    });

    test('rejects zero contributions', () async {
      final memberId = await seedMember();

      await expectLater(
        repository.save(
          Contribution(
            id: 0,
            tripId: 1,
            memberId: memberId,
            amountMinor: 0,
            note: null,
            createdAt: DateTime.now(),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects negative contributions', () async {
      final memberId = await seedMember();

      await expectLater(
        repository.save(
          Contribution(
            id: 0,
            tripId: 1,
            memberId: memberId,
            amountMinor: -500,
            note: null,
            createdAt: DateTime.now(),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await db.contributionDao.getByTrip(1), isEmpty);
    });
  });
}
