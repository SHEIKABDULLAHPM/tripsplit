import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/trips/data/trip_repository_impl.dart';
import 'package:tripsplit/features/trips/domain/trip.dart';
import 'package:tripsplit/features/trips/domain/trip_repository.dart';

void main() {
  group('TripRepositoryImpl', () {
    late AppDatabase db;
    late TripRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TripRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    test(
      'createWithSetup persists trip, members and contributions atomically',
      () async {
        final tripId = await repository.createWithSetup(
          name: 'Beach Trip',
          budgetMinor: 500_00,
          members: const [
            NewMemberDraft(name: 'Suki', contributionMinor: 300_00),
            NewMemberDraft(name: ' Manu ', contributionMinor: 200_00),
          ],
        );

        final trip = await repository.findById(tripId);
        expect(trip, isNotNull);
        expect(trip!.name, 'Beach Trip');
        expect(trip.totalBudgetMinor, 500_00);

        final members = await db.memberDao.getByTrip(tripId);
        expect(members, hasLength(2));
        expect(members.map((m) => m.name), containsAll(['Suki', 'Manu']));

        final contributions = await db.contributionDao.getByTrip(tripId);
        final total = contributions.fold<int>(
          0,
          (sum, c) => sum + c.amountMinor,
        );
        expect(total, 500_00);
      },
    );

    test('watchAll emits the created trip', () async {
      final updates = <List<Trip>>[];
      final sub = repository.watchAll().listen(updates.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final tripId = await repository.createWithSetup(
        name: 'Camping',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(updates, isNotEmpty);
      expect(updates.last, hasLength(1));
      expect(updates.last.single.id, tripId);
    });

    test('save updates an existing trip', () async {
      final tripId = await repository.createWithSetup(
        name: 'Initial',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );

      final trip = (await repository.findById(tripId))!;
      await repository.save(
        trip.copyWith(name: 'Renamed', totalBudgetMinor: 200_00),
      );

      final updated = await repository.findById(tripId);
      expect(updated!.name, 'Renamed');
      expect(updated.totalBudgetMinor, 200_00);
    });

    test('deleteById removes the trip and its dependent rows', () async {
      final tripId = await repository.createWithSetup(
        name: 'Gone',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );

      await repository.deleteById(tripId);

      expect(await repository.findById(tripId), isNull);
      expect(await db.memberDao.getByTrip(tripId), isEmpty);
    });

    test('createWithSetup rejects a duplicate trip name', () async {
      await repository.createWithSetup(
        name: 'Beach Trip',
        budgetMinor: 500_00,
        members: const [
          NewMemberDraft(name: 'Suki', contributionMinor: 500_00),
        ],
      );

      await expectLater(
        repository.createWithSetup(
          name: 'Beach Trip',
          budgetMinor: 100_00,
          members: const [NewMemberDraft(name: 'Maya')],
        ),
        throwsA(isA<ValidationException>()),
      );

      // The atomic setup rolled back: no duplicate trip or stray members.
      expect(await db.tripDao.getAll(), hasLength(1));
      expect(
        await db.memberDao.getByTrip((await db.tripDao.getAll()).single.id),
        hasLength(1),
      );
    });

    test('createWithSetup rejects duplicate member names', () async {
      await expectLater(
        repository.createWithSetup(
          name: 'Dupe Members',
          budgetMinor: 100_00,
          members: const [
            NewMemberDraft(name: 'Suki', contributionMinor: 100_00),
            NewMemberDraft(name: 'Suki'),
          ],
        ),
        throwsA(isA<ValidationException>()),
      );

      // Atomic rollback: no trip or members were persisted.
      expect(await db.tripDao.getAll(), isEmpty);
    });

    test('save throws when the trip no longer exists', () async {
      final id = await repository.createWithSetup(
        name: 'Gone',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );
      final trip = (await repository.findById(id))!;
      await repository.deleteById(id);

      await expectLater(
        repository.save(trip),
        throwsA(isA<ValidationException>()),
      );
    });

    test('save rejects renaming onto an existing trip name', () async {
      await repository.createWithSetup(
        name: 'Alpha',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );
      final betaId = await repository.createWithSetup(
        name: 'Beta',
        budgetMinor: 100_00,
        members: const [NewMemberDraft(name: 'Leo')],
      );

      final beta = (await repository.findById(betaId))!;
      await expectLater(
        repository.save(beta.copyWith(name: 'Alpha')),
        throwsA(isA<ValidationException>()),
      );
    });

    test('createWithSetup rejects a negative budget', () async {
      expect(
        () => repository.createWithSetup(
          name: 'Negative',
          budgetMinor: -1,
          members: const [NewMemberDraft(name: 'Leo')],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await db.tripDao.getAll(), isEmpty);
    });

    test('data survives a database reopen', () async {
      final file = File(
        '${Directory.systemTemp.createTempSync('tripsplit').path}/persist.db',
      );
      var fileDb = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file),
      );
      var fileRepo = TripRepositoryImpl(fileDb);

      final tripId = await fileRepo.createWithSetup(
        name: 'Persistent',
        budgetMinor: 250_00,
        members: const [NewMemberDraft(name: 'Aya', contributionMinor: 250_00)],
      );
      await fileDb.closeDatabase();

      fileDb = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
      fileRepo = TripRepositoryImpl(fileDb);
      addTearDown(fileDb.closeDatabase);

      final trip = await fileRepo.findById(tripId);
      expect(trip, isNotNull);
      expect(trip!.name, 'Persistent');
      expect(trip.totalBudgetMinor, 250_00);
      expect(await fileDb.memberDao.getByTrip(tripId), hasLength(1));
    });
  });
}
