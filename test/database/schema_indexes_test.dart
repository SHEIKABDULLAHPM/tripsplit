import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tripsplit/database/app_database.dart';

/// Guards the query indexes that back the app's reactive views.
///
/// `createAll` on a fresh install must produce exactly the same indexes that
/// the v6 -> v7 migration step creates for existing databases, otherwise a
/// drifted name/column here would silently leave an index missing (or
/// duplicated) on upgraded installs. Keep the expected map in lock-step with
/// both the `@TableIndex` annotations and the migration step.
void main() {
  group('Schema indexes', () {
    test('fresh schema creates the expected query indexes', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final rows = await db
          .customSelect(
            'SELECT name, tbl_name, sql FROM sqlite_master '
            "WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name",
          )
          .get();

      final actual = <String, String>{};
      for (final row in rows) {
        final name = row.read<String>('name');
        final sql = row.read<String>('sql')!;
        final table = row.read<String>('tbl_name');
        final columns = RegExp(
          r'\(([^)]+)\)',
        ).firstMatch(sql)!.group(1)!.replaceAll(' ', '');
        actual['$name'] = '$table($columns)';
      }

      final expected = <String, String>{
        'idx_members_trip': 'members(trip_id)',
        'idx_locations_trip': 'locations(trip_id)',
        'idx_segments_trip': 'travel_segments(trip_id)',
        'idx_participations_member': 'member_segment_participations(member_id)',
        'idx_participations_segment':
            'member_segment_participations(segment_id)',
        'idx_teams_trip': 'teams(trip_id)',
        'idx_team_members_team': 'team_members(team_id)',
        'idx_team_members_member': 'team_members(member_id)',
        'idx_contributions_trip': 'contributions(trip_id)',
        'idx_contributions_member': 'contributions(member_id)',
        'idx_expenses_trip': 'expenses(trip_id)',
        'idx_expenses_payer': 'expenses(payer_member_id)',
        'idx_shares_expense': 'expense_shares(expense_id)',
        'idx_shares_member': 'expense_shares(member_id)',
        'idx_payments_expense': 'expense_payments(expense_id)',
        'idx_payments_member': 'expense_payments(member_id)',
        'idx_expense_teams_expense': 'expense_teams(expense_id)',
        'idx_expense_teams_team': 'expense_teams(team_id)',
        'idx_settlements_trip': 'settlements(trip_id)',
        'idx_settlements_from_member': 'settlements(from_member_id)',
        'idx_settlements_to_member': 'settlements(to_member_id)',
        'idx_notes_trip': 'notes(trip_id)',
      };

      expect(actual, expected);
      await db.closeDatabase();
    });

    test(
      'indexes are usable by query planner after a v6 -> v7 upgrade',
      () async {
        // A file-backed connection so the database can be closed and re-opened
        // at a lower schema version (the standard Drift upgrade-test pattern).
        final dir = await Directory.systemTemp.createTemp(
          'tripsplit_migration_test',
        );
        final file = File(p.join(dir.path, 'test.db'));
        final fresh = AppDatabase.forTesting(NativeDatabase(file));
        // First query opens the connection and runs `createAll`.
        await fresh.customSelect('SELECT 1').get();

        // Simulate a pre-v7 database by dropping the query indexes and rolling
        // the schema version back to 6. The tables/columns remain, so reopening
        // runs the v6 -> v7 migration, which must re-create every index.
        for (final name in [
          'idx_members_trip',
          'idx_locations_trip',
          'idx_segments_trip',
          'idx_participations_member',
          'idx_participations_segment',
          'idx_teams_trip',
          'idx_team_members_team',
          'idx_team_members_member',
          'idx_contributions_trip',
          'idx_contributions_member',
          'idx_expenses_trip',
          'idx_expenses_payer',
          'idx_shares_expense',
          'idx_shares_member',
          'idx_payments_expense',
          'idx_payments_member',
          'idx_expense_teams_expense',
          'idx_expense_teams_team',
          'idx_settlements_from_member',
          'idx_settlements_to_member',
          'idx_notes_trip',
        ]) {
          await fresh.customStatement('DROP INDEX IF EXISTS $name;');
        }
        await fresh.customStatement('PRAGMA user_version = 6;');
        await fresh.closeDatabase();

        // Reopening the same file applies onUpgrade(6 -> 7).
        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        await upgraded.customSelect('SELECT 1').get();
        final count =
            (await upgraded
                    .customSelect(
                      'SELECT COUNT(*) AS c FROM sqlite_master '
                      "WHERE type = 'index' AND name LIKE 'idx_%'",
                    )
                    .get())
                .single
                .read<int>('c');
        expect(count, 22, reason: 'migration should restore every query index');
        await upgraded.closeDatabase();
        await dir.delete(recursive: true);
      },
    );
  });
}
