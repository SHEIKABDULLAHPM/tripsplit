import 'package:drift/drift.dart';

import 'members.dart';
import 'trips.dart';

/// An initial amount contributed by a member into the trip pool.
///
/// Contributions are source transactions; balances are derived from them
/// together with expenses and settlements at read time.
@DataClassName('ContributionRow')
@TableIndex(name: 'idx_contributions_trip', columns: {#tripId})
@TableIndex(name: 'idx_contributions_member', columns: {#memberId})
class Contributions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
}
