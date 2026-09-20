import 'package:drift/drift.dart';

import 'trips.dart';

/// A free-form note attached to a trip.
///
/// Notes are lightweight, trip-scoped reminders (addresses, packing lists,
/// booking references) that are not part of any money calculation.
@DataClassName('NoteRow')
@TableIndex(name: 'idx_notes_trip', columns: {#tripId})
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get body => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
}
