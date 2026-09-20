import 'package:drift/drift.dart';

import 'expenses.dart';
import 'members.dart';

/// Splits a single [Expenses] entry across members.
///
/// `shareMinor` is the portion of the expense assigned to a member. The
/// recorded [Expenses.amountMinor] is the sum of its shares; the sum rule is
/// enforced by repositories, not by duplicating a total column.
@DataClassName('ExpenseShareRow')
@TableIndex(name: 'idx_shares_expense', columns: {#expenseId})
@TableIndex(name: 'idx_shares_member', columns: {#memberId})
class ExpenseShares extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get expenseId =>
      integer().references(Expenses, #id, onDelete: KeyAction.cascade)();
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();
  IntColumn get shareMinor => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {expenseId, memberId},
  ];
}
