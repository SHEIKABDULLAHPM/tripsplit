import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/constants/app_constants.dart';
import 'package:tripsplit/database/app_database.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    test('reports the configured schema version', () {
      expect(db.schemaVersion, AppConstants.databaseSchemaVersion);
    });

    test('opens successfully and exposes DAOs', () {
      expect(db.tripDao, isNotNull);
      expect(db.memberDao, isNotNull);
      expect(db.contributionDao, isNotNull);
      expect(db.expenseDao, isNotNull);
      expect(db.settlementDao, isNotNull);
    });

    test('creates the schema and persists a trip via the DAO', () async {
      final id = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Summer in Rome'),
      );

      final trips = await db.tripDao.getAll();
      expect(trips, hasLength(1));
      expect(trips.first.id, id);
      expect(trips.first.name, 'Summer in Rome');
      expect(trips.first.currencyCode, 'INR');
    });

    test('watches trips reactively', () async {
      final updates = <int>[];
      final sub = db.tripDao.watchAll().listen(
        (List<TripRow> trips) => updates.add(trips.length),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.tripDao.insert(TripsCompanion.insert(name: 'Beach Trip'));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(updates, containsAll([0, 1]));
    });

    test('enforces foreign keys (member requires an existing trip)', () async {
      expect(
        () => db.memberDao.insert(
          MembersCompanion.insert(tripId: 999, name: 'Ghost'),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('cascades deletes from trips to members', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Group Trip'),
      );
      await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Alice'),
      );

      await db.tripDao.deleteById(tripId);

      final members = await db.memberDao.getByTrip(tripId);
      expect(members, isEmpty);
    });
  });
}
