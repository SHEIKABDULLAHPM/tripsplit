import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/contributions.dart';
part 'contribution_dao.g.dart';

/// Low-level data access for contributions.
@DriftAccessor(tables: [Contributions])
class ContributionDao extends DatabaseAccessor<AppDatabase>
    with _$ContributionDaoMixin {
  ContributionDao(super.db);

  Stream<List<ContributionRow>> watchAll() => (select(
    contributions,
  )..orderBy([(c) => OrderingTerm.desc(c.createdAt)])).watch();

  Stream<List<ContributionRow>> watchByTrip(int tripId) =>
      (select(contributions)
            ..where((c) => c.tripId.equals(tripId))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .watch();

  Future<List<ContributionRow>> getByTrip(int tripId) =>
      (select(contributions)
            ..where((c) => c.tripId.equals(tripId))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .get();

  Future<ContributionRow?> getById(int id) =>
      (select(contributions)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> insert(ContributionsCompanion entry) =>
      into(contributions).insert(entry);

  Future<bool> updateById(int id, ContributionsCompanion entry) async =>
      (await (update(
        contributions,
      )..where((c) => c.id.equals(id))).write(entry)) ==
      1;

  Future<int> deleteById(int id) =>
      (delete(contributions)..where((c) => c.id.equals(id))).go();
}
