import 'package:drift/drift.dart';

import 'trips.dart';

/// An organizational grouping of trip members (e.g. "Dhar's Team").
///
/// Teams are labels only: membership does NOT force a member into every team
/// expense. Each expense explicitly picks its scope and participants, defaulting
/// to the team's members or a segment's participants when that scope is chosen.
@DataClassName('TeamRow')
@TableIndex(name: 'idx_teams_trip', columns: {#tripId})
class Teams extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {tripId, name},
  ];
}
