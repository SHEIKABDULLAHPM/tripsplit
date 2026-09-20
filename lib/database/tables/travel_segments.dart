import 'package:drift/drift.dart';

import 'locations.dart';
import 'trips.dart';

/// An ordered leg of a trip's journey, e.g. "Erode → Salem".
///
/// Segments exist solely so that expense participation can be derived from who
/// actually travelled; they never imply navigation or GPS.
@DataClassName('TravelSegmentRow')
@TableIndex(name: 'idx_segments_trip', columns: {#tripId})
class TravelSegments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();

  /// Ordering within the trip (0, 1, 2, ...).
  IntColumn get sequence => integer()();
  @ReferenceName('segmentStartRefs')
  IntColumn get startLocationId =>
      integer().references(Locations, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('segmentEndRefs')
  IntColumn get endLocationId =>
      integer().references(Locations, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
