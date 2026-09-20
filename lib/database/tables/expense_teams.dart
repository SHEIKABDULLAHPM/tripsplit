import 'package:drift/drift.dart';

import 'expenses.dart';
import 'teams.dart';

/// Joins an expense to every team it applies to (many-to-many).
///
/// A team-centered expense recorded once can be shared by several teams at
/// once (e.g. a ₹4,000 trip booking split across two teams of five). The
/// legacy single `expenses.teamId` column is kept for back-compatibility and
/// always mirrors the first team stored here whenever a team-scoped expense is
/// written.
@DataClassName('ExpenseTeamRow')
@TableIndex(name: 'idx_expense_teams_expense', columns: {#expenseId})
@TableIndex(name: 'idx_expense_teams_team', columns: {#teamId})
class ExpenseTeams extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get expenseId =>
      integer().references(Expenses, #id, onDelete: KeyAction.cascade)();
  IntColumn get teamId =>
      integer().references(Teams, #id, onDelete: KeyAction.cascade)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {expenseId, teamId},
  ];
}
