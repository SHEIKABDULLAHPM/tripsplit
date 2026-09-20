import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/trips.dart';
part 'trip_dao.g.dart';

/// Low-level data access for trips.
///
/// This is the persistence boundary for the trips feature. Repositories
/// (feature layer) depend on this DAO through the database; widgets never
/// access it directly.
@DriftAccessor(tables: [Trips])
class TripDao extends DatabaseAccessor<AppDatabase> with _$TripDaoMixin {
  TripDao(super.db);

  Stream<List<TripRow>> watchAll() =>
      (select(trips)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<List<TripRow>> getAll() =>
      (select(trips)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<TripRow?> getById(int id) =>
      (select(trips)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<TripRow?> watchById(int id) =>
      (select(trips)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insert(TripsCompanion entry) => into(trips).insert(entry);

  Future<bool> updateById(int id, TripsCompanion entry) async =>
      (await (update(trips)..where((t) => t.id.equals(id))).write(entry)) == 1;

  Future<int> deleteById(int id) =>
      (delete(trips)..where((t) => t.id.equals(id))).go();
}
