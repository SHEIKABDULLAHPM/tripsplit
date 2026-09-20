import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/settlements.dart';
part 'settlement_dao.g.dart';

/// Low-level data access for settlements.
@DriftAccessor(tables: [Settlements])
class SettlementDao extends DatabaseAccessor<AppDatabase>
    with _$SettlementDaoMixin {
  SettlementDao(super.db);

  Stream<List<SettlementRow>> watchByTrip(int tripId) =>
      (select(settlements)
            ..where((s) => s.tripId.equals(tripId))
            ..orderBy([(s) => OrderingTerm.desc(s.settledAt)]))
          .watch();

  Future<List<SettlementRow>> getByTrip(int tripId) =>
      (select(settlements)
            ..where((s) => s.tripId.equals(tripId))
            ..orderBy([(s) => OrderingTerm.desc(s.settledAt)]))
          .get();

  Future<SettlementRow?> getById(int id) =>
      (select(settlements)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<bool> hasSettlementsForMember(int memberId) async {
    final asFrom = await (select(
      settlements,
    )..where((s) => s.fromMemberId.equals(memberId))).get();
    final asTo = await (select(
      settlements,
    )..where((s) => s.toMemberId.equals(memberId))).get();
    return asFrom.isNotEmpty || asTo.isNotEmpty;
  }

  Future<int> insert(SettlementsCompanion entry) =>
      into(settlements).insert(entry);

  Future<bool> updateById(int id, SettlementsCompanion entry) async =>
      (await (update(
        settlements,
      )..where((s) => s.id.equals(id))).write(entry)) ==
      1;

  Future<int> deleteById(int id) =>
      (delete(settlements)..where((s) => s.id.equals(id))).go();
}
