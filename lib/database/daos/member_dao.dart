import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/members.dart';
part 'member_dao.g.dart';

/// Low-level data access for trip members.
@DriftAccessor(tables: [Members])
class MemberDao extends DatabaseAccessor<AppDatabase> with _$MemberDaoMixin {
  MemberDao(super.db);

  Stream<List<MemberRow>> watchAll() =>
      (select(members)..orderBy([(m) => OrderingTerm.asc(m.name)])).watch();

  Stream<List<MemberRow>> watchByTrip(int tripId) =>
      (select(members)
            ..where((m) => m.tripId.equals(tripId))
            ..orderBy([(m) => OrderingTerm.asc(m.name)]))
          .watch();

  Future<List<MemberRow>> getByTrip(int tripId) =>
      (select(members)
            ..where((m) => m.tripId.equals(tripId))
            ..orderBy([(m) => OrderingTerm.asc(m.name)]))
          .get();

  Future<MemberRow?> getById(int id) =>
      (select(members)..where((m) => m.id.equals(id))).getSingleOrNull();

  Stream<List<MemberRow>> watchByIds(List<int> ids) {
    if (ids.isEmpty) {
      return const Stream.empty();
    }
    return (select(members)..where((m) => m.id.isIn(ids))).watch();
  }

  Future<List<MemberRow>> getByIds(List<int> ids) {
    if (ids.isEmpty) {
      return Future.value(const []);
    }
    return (select(members)..where((m) => m.id.isIn(ids))).get();
  }

  Future<int> insert(MembersCompanion entry) => into(members).insert(entry);

  Future<bool> updateById(int id, MembersCompanion entry) async =>
      (await (update(members)..where((m) => m.id.equals(id))).write(entry)) ==
      1;

  Future<int> deleteById(int id) =>
      (delete(members)..where((m) => m.id.equals(id))).go();
}
