import 'package:drift/drift.dart';

import 'trips.dart';

/// A named place on a trip's journey (e.g. "Erode", "Salem").
///
/// Locations are simple user-entered names that anchor travel segments and a
/// member's joining/leaving point. They are not GPS coordinates.
@DataClassName('LocationRow')
@TableIndex(name: 'idx_locations_trip', columns: {#tripId})
class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {tripId, name},
  ];
}
