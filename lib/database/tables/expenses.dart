import 'package:drift/drift.dart';

import 'members.dart';
import 'teams.dart';
import 'travel_segments.dart';
import 'trips.dart';

/// A single expense recorded during a trip.
///
/// Source transaction: balances are derived, never stored here.
@DataClassName('ExpenseRow')
@TableIndex(name: 'idx_expenses_trip', columns: {#tripId})
@TableIndex(name: 'idx_expenses_payer', columns: {#payerMemberId})
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  IntColumn get payerMemberId =>
      integer().references(Members, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text().withLength(min: 1, max: 200)();

  /// What the expense applies to. Drives how participants are defaulted in the
  /// UI (individual / shared / team / segment / custom). See `ExpenseScope`.
  TextColumn get scope => text().withDefault(const Constant('shared'))();
  IntColumn get segmentId => integer()
      .references(TravelSegments, #id, onDelete: KeyAction.setNull)
      .nullable()();
  IntColumn get teamId => integer()
      .references(Teams, #id, onDelete: KeyAction.setNull)
      .nullable()();

  /// Full price of the expense, in minor units. Also the sum of all payments
  /// in [ExpensePayments].
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();

  /// Cash actually paid out of the group's pocket that is NOT part of the
  /// group sharing. Shareable group amount = [amountMinor] -
  /// [externalAmountMinor]. The external portion is attributed to the primary
  /// payer's group outlay so that `sum(shares) == group amount`.
  IntColumn get externalAmountMinor =>
      integer().withDefault(const Constant(0))();
  TextColumn get category => text().nullable()();
  DateTimeColumn get spentAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
