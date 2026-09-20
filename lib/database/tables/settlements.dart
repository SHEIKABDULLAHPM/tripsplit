import 'package:drift/drift.dart';

import 'members.dart';
import 'trips.dart';

/// A settlement that transfers money from one member to another.
///
/// Settlements are source transactions used to mark balances as resolved.
@DataClassName('SettlementRow')
@TableIndex(name: 'idx_settlements_trip', columns: {#tripId})
@TableIndex(name: 'idx_settlements_from_member', columns: {#fromMemberId})
@TableIndex(name: 'idx_settlements_to_member', columns: {#toMemberId})
class Settlements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();

  /// Reference between a settlement's payer and the members table.
  @ReferenceName('settlementFromMemberRefs')
  IntColumn get fromMemberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();

  /// Reference between a settlement's payee and the members table.
  @ReferenceName('settlementToMemberRefs')
  IntColumn get toMemberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();

  /// Cash actually transferred so far; accumulates across partial payments.
  IntColumn get amountPaidMinor => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  DateTimeColumn get settledAt => dateTime().clientDefault(DateTime.now)();

  /// When the transfer was fully paid, if it is.
  DateTimeColumn get paidAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
