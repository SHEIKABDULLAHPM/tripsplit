import 'package:drift/drift.dart';

/// A trip a group of members goes on together.
///
/// The `currencyCode` is declared at trip level for the MVP. All monetary
/// amounts are stored in minor units (e.g. cents) for the trip currency.
@DataClassName('TripRow')
class Trips extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();
  TextColumn get currencyCode =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('INR'))();

  /// Planned group budget in minor units; separate from contributions.
  IntColumn get totalBudgetMinor => integer().withDefault(const Constant(0))();

  /// Journey starting point as a simple text label (e.g. "Erode").
  TextColumn get startLocation => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {name},
  ];
}
