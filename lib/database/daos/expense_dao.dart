import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expense_shares.dart';
import '../tables/expense_teams.dart';
import '../tables/expenses.dart';
part 'expense_dao.g.dart';

/// Low-level data access for expenses, their shares and team links.
@DriftAccessor(tables: [Expenses, ExpenseShares, ExpenseTeams])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Stream<List<ExpenseRow>> watchAll() => (select(
    expenses,
  )..orderBy([(e) => OrderingTerm.desc(e.createdAt)])).watch();

  Stream<List<ExpenseRow>> watchByTrip(int tripId) =>
      (select(expenses)
            ..where((e) => e.tripId.equals(tripId))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .watch();

  Future<List<ExpenseRow>> getByTrip(int tripId) =>
      (select(expenses)
            ..where((e) => e.tripId.equals(tripId))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .get();

  Future<List<ExpenseShareRow>> getSharesByTrip(int tripId) async {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expenseShares,
    )..where((s) => s.expenseId.isInQuery(expenseIds))).get();
  }

  Stream<List<ExpenseShareRow>> watchSharesByTrip(int tripId) {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expenseShares,
    )..where((s) => s.expenseId.isInQuery(expenseIds))).watch();
  }

  Future<bool> hasExpensesByPayer(int memberId) async => (await (select(
    expenses,
  )..where((e) => e.payerMemberId.equals(memberId))).get()).isNotEmpty;

  Future<bool> hasSharesForMember(int memberId) async => (await (select(
    expenseShares,
  )..where((s) => s.memberId.equals(memberId))).get()).isNotEmpty;

  Future<List<ExpenseRow>> byTeam(int teamId) {
    final linkedIds = selectOnly(expenseTeams)
      ..addColumns([expenseTeams.expenseId])
      ..where(expenseTeams.teamId.equals(teamId));
    return (select(
      expenses,
    )..where((e) => e.teamId.equals(teamId) | e.id.isInQuery(linkedIds))).get();
  }

  // -- Team links (many-to-many expenses ↔ teams) ------------------------------

  Stream<List<ExpenseTeamRow>> watchTeamLinksByTrip(int tripId) {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expenseTeams,
    )..where((t) => t.expenseId.isInQuery(expenseIds))).watch();
  }

  Future<List<ExpenseTeamRow>> getTeamLinksByTrip(int tripId) async {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expenseTeams,
    )..where((t) => t.expenseId.isInQuery(expenseIds))).get();
  }

  Future<List<ExpenseTeamRow>> getTeamLinksFor(int expenseId) =>
      (select(expenseTeams)..where((t) => t.expenseId.equals(expenseId))).get();

  Stream<List<ExpenseTeamRow>> watchTeamLinksFor(int expenseId) => (select(
    expenseTeams,
  )..where((t) => t.expenseId.equals(expenseId))).watch();

  Future<int> insertTeamLink(int expenseId, int teamId) => into(
    expenseTeams,
  ).insert(ExpenseTeamsCompanion.insert(expenseId: expenseId, teamId: teamId));

  Future<void> insertTeamLinks(int expenseId, List<int> teamIds) async {
    for (final teamId in teamIds) {
      await insertTeamLink(expenseId, teamId);
    }
  }

  Future<int> deleteTeamLinksFor(int expenseId) =>
      (delete(expenseTeams)..where((t) => t.expenseId.equals(expenseId))).go();

  Future<ExpenseRow?> getById(int id) =>
      (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Stream<ExpenseRow?> watchById(int id) =>
      (select(expenses)..where((e) => e.id.equals(id))).watchSingleOrNull();

  Future<int> insert(ExpensesCompanion entry) => into(expenses).insert(entry);

  Future<bool> updateById(int id, ExpensesCompanion entry) async =>
      (await (update(expenses)..where((e) => e.id.equals(id))).write(entry)) ==
      1;

  Future<List<ExpenseShareRow>> getSharesFor(int expenseId) => (select(
    expenseShares,
  )..where((s) => s.expenseId.equals(expenseId))).get();

  Future<int> insertShare(ExpenseSharesCompanion entry) =>
      into(expenseShares).insert(entry);

  Future<int> deleteSharesFor(int expenseId) =>
      (delete(expenseShares)..where((s) => s.expenseId.equals(expenseId))).go();

  Future<int> deleteById(int id) =>
      (delete(expenses)..where((e) => e.id.equals(id))).go();
}
