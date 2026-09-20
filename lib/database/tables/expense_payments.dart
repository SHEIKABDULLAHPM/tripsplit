import 'package:drift/drift.dart';

import 'expenses.dart';
import 'members.dart';
import 'teams.dart';

/// A cash contribution one member made toward a single expense.
///
/// The sum of an expense's payment rows equals the expense's full amount.
/// The `payerMemberId` column on the expense is kept as the primary payer for
/// display and migration compatibility; when payment rows exist they are
/// authoritative for calculations.
@DataClassName('ExpensePaymentRow')
@TableIndex(name: 'idx_payments_expense', columns: {#expenseId})
@TableIndex(name: 'idx_payments_member', columns: {#memberId})
class ExpensePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get expenseId =>
      integer().references(Expenses, #id, onDelete: KeyAction.cascade)();
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();

  /// Team this payer paid on behalf of, for team-scoped expenses. Null for
  /// non-team payers. A payer recorded for a team must be a member of it.
  IntColumn get teamId => integer()
      .references(Teams, #id, onDelete: KeyAction.setNull)
      .nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {expenseId, memberId},
  ];
}
