import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import 'daos/contribution_dao.dart';
import 'daos/expense_dao.dart';
import 'daos/journey_dao.dart';
import 'daos/member_dao.dart';
import 'daos/note_dao.dart';
import 'daos/settlement_dao.dart';
import 'daos/trip_dao.dart';
import 'tables/contributions.dart';
import 'tables/expense_payments.dart';
import 'tables/expense_shares.dart';
import 'tables/expense_teams.dart';
import 'tables/expenses.dart';
import 'tables/locations.dart';
import 'tables/member_segment_participations.dart';
import 'tables/members.dart';
import 'tables/notes.dart';
import 'tables/settlements.dart';
import 'tables/team_members.dart';
import 'tables/teams.dart';
import 'tables/travel_segments.dart';
import 'tables/trips.dart';
part 'app_database.g.dart';

/// Central Drift database definition.
///
/// This class wires together the schema (tables), DAOs, migration strategy,
/// and connection lifecycle. Application code accesses the database exclusively
/// through [DatabaseAccessor] subclasses (DAOs), which are exposed as getters
/// on this class.
@DriftDatabase(
  tables: [
    Trips,
    Members,
    Locations,
    TravelSegments,
    MemberSegmentParticipations,
    Teams,
    TeamMembers,
    Contributions,
    Expenses,
    ExpenseShares,
    ExpensePayments,
    ExpenseTeams,
    Settlements,
    Notes,
  ],
  daos: [
    TripDao,
    MemberDao,
    ContributionDao,
    ExpenseDao,
    SettlementDao,
    JourneyDao,
    NoteDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Exposed for widget/integration tests that inject a pre-warmed executor.
  ///
  /// Query streams stop synchronously (no drift keep-alive timer is left
  /// pending) so tests can `await closeDatabase()` even under a test's fake
  /// async zone.
  factory AppDatabase.forTesting(QueryExecutor executor) =>
      AppDatabase._injected(
        DatabaseConnection(executor, closeStreamsSynchronously: true),
      );

  AppDatabase._injected(super.e);

  @override
  int get schemaVersion => AppConstants.databaseSchemaVersion;

  // -- Migrations -------------------------------------------------------------

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 -> v2: budget on trips, edit-tracking timestamps, and partial
      // settlement support.
      if (from < 2) {
        await m.addColumn(trips, trips.totalBudgetMinor);
        await m.addColumn(expenses, expenses.updatedAt);
        await m.addColumn(settlements, settlements.amountPaidMinor);
        await m.addColumn(settlements, settlements.paidAt);
        await m.addColumn(settlements, settlements.updatedAt);
      }
      // v2 -> v3: external (non-group) portion of an expense.
      if (from < 3) {
        await m.addColumn(expenses, expenses.externalAmountMinor);
      }
      // v3 -> v4: the journey model (locations, travel segments, per-member
      // participation), teams, expense scopes, and multiple payers per expense.
      if (from < 4) {
        await m.createTable(locations);
        await m.createTable(travelSegments);
        await m.createTable(memberSegmentParticipations);
        await m.createTable(teams);
        await m.createTable(teamMembers);
        await m.createTable(expensePayments);

        await m.addColumn(trips, trips.startLocation);
        await m.addColumn(members, members.joinLocationId);
        await m.addColumn(members, members.leaveLocationId);
        await m.addColumn(expenses, expenses.scope);
        await m.addColumn(expenses, expenses.segmentId);
        await m.addColumn(expenses, expenses.teamId);

        // Backfill one payment row per existing expense so the payments table
        // becomes authoritative while the primary payer column stays intact.
        await customStatement(
          'INSERT INTO expense_payments (expense_id, member_id, amount_minor) '
          'SELECT id, payer_member_id, amount_minor FROM expenses;',
        );
      }
      // v4 -> v5: trip-scoped notes.
      if (from < 5) {
        await m.createTable(notes);
      }
      // v5 -> v6: an expense can apply to several teams at once (join table)
      // and each team payer records which team they paid on behalf of.
      if (from < 6) {
        await m.createTable(expenseTeams);
        await m.addColumn(expensePayments, expensePayments.teamId);

        // Backfill the join table from the legacy single-team column.
        await customStatement(
          'INSERT INTO expense_teams (expense_id, team_id) '
          'SELECT id, team_id FROM expenses WHERE team_id IS NOT NULL;',
        );
        // Attribute every payment of a legacy team expense to that team.
        await customStatement(
          'UPDATE expense_payments SET team_id = ('
          '  SELECT team_id FROM expenses '
          '  WHERE expenses.id = expense_payments.expense_id'
          ') WHERE EXISTS ('
          '  SELECT 1 FROM expenses '
          '  WHERE expenses.id = expense_payments.expense_id '
          '  AND expenses.team_id IS NOT NULL'
          ');',
        );
      }
      // v6 -> v7: performance indexes on the columns that the reactive trip /
      // home / journey views filter by on every stream emission. Fresh
      // installs get these via `createAll`; existing databases are upgraded
      // here. All statements are idempotent.
      if (from < 7) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_members_trip ON members (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_locations_trip ON locations (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_segments_trip ON travel_segments (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_participations_member '
          'ON member_segment_participations (member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_participations_segment '
          'ON member_segment_participations (segment_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_teams_trip ON teams (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_team_members_team ON team_members (team_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_team_members_member ON team_members (member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_contributions_trip ON contributions (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_contributions_member ON contributions (member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_trip ON expenses (trip_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_payer ON expenses (payer_member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_shares_expense ON expense_shares (expense_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_shares_member ON expense_shares (member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_expense ON expense_payments (expense_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_member ON expense_payments (member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expense_teams_expense ON expense_teams (expense_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expense_teams_team ON expense_teams (team_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_settlements_from_member '
          'ON settlements (from_member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_settlements_to_member '
          'ON settlements (to_member_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_notes_trip ON notes (trip_id);',
        );
      }
    },
    beforeOpen: (details) async {
      // Enforce foreign-key constraints and WAL mode.
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
    },
  );

  // -- Connection -------------------------------------------------------------

  static QueryExecutor _openConnection() {
    if (const bool.fromEnvironment('dart.vm.product') == false &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return NativeDatabase.memory();
    }
    return _nativeConnection();
  }

  static QueryExecutor _nativeConnection() => LazyDatabase(() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(
      documentsDirectory.path,
      AppConstants.databaseFileName,
    );
    final file = File(dbPath);
    return NativeDatabase.createInBackground(file);
  });

  // -- Query helpers ----------------------------------------------------------

  Future<void> closeDatabase() => close();
}
