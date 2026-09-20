import 'package:drift/drift.dart';

import 'locations.dart';
import 'trips.dart';

/// A participant of a [Trips] trip.
@DataClassName('MemberRow')
@TableIndex(name: 'idx_members_trip', columns: {#tripId})
class Members extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// Where this member joined the journey (nullable = from the start).
  IntColumn get joinLocationId => integer()
      .references(Locations, #id, onDelete: KeyAction.setNull)
      .nullable()();

  /// Where this member left the journey (nullable = until the end).
  IntColumn get leaveLocationId => integer()
      .references(Locations, #id, onDelete: KeyAction.setNull)
      .nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {tripId, name},
  ];
}
