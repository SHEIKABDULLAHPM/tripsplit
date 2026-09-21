import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/app/theme/app_theme.dart';
import 'package:tripsplit/app/widgets/help_support_popup.dart';
import 'package:tripsplit/app/widgets/home_screen.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/balances/presentation/balances_screen.dart';
import 'package:tripsplit/features/expenses/presentation/expense_management_screen.dart';
import 'package:tripsplit/features/members/presentation/people_screen.dart';
import 'package:tripsplit/features/settlements/presentation/settlements_screen.dart';
import 'package:tripsplit/features/trips/presentation/trip_dashboard_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Reports the Help & Support popup as already shown so these resize
/// smoke tests are not blocked by the app-open popup.
class _ShownHelpSupportPopupFlag extends HelpSupportPopupFlag {
  @override
  bool build() => true;
}

/// Exercises the redesigned screens at three widths plus a large text scale to
/// catch overflow exceptions before they ship.
void main() {
  late AppDatabase db;
  late int tripId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tripId = await db.tripDao.insert(
      TripsCompanion.insert(name: 'Responsive Test Trip'),
    );
    await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Alice'),
    );
    await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Bob'),
    );
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  /// Wraps a screen in a fixed-size MaterialApp with the app theme.
  Widget buildScreen(Widget child, BoxConstraints constraints) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );

  Widget buildHomeScreen(BoxConstraints constraints) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      helpSupportPopupFlagProvider.overrideWith(_ShownHelpSupportPopupFlag.new),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: HomeScreen()),
    ),
  );

  Future<void> assertNoOverflow(
    WidgetTester tester,
    Widget app,
    BoxConstraints constraints,
  ) async {
    await tester.binding.setSurfaceSize(
      Size(constraints.maxWidth, constraints.maxHeight),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // RenderFlex overflow is thrown during layout and caught by the framework
    // as a FlutterError. tester.takeException() surfaces it.
    final error = tester.takeException();
    expect(
      error,
      isNull,
      reason:
          'Unexpected exception at ${constraints.maxWidth}x${constraints.maxHeight}',
    );

    // Unmount so pending Drift query-stream timers are flushed before the
    // test's pending-timer invariant is checked.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  final screenSizes = {
    '360x640': const BoxConstraints.expand(width: 360, height: 640),
    '390x844': const BoxConstraints.expand(width: 390, height: 844),
    '430x932': const BoxConstraints.expand(width: 430, height: 932),
  };

  group('Responsive smoke tests', () {
    for (final entry in screenSizes.entries) {
      testWidgets('HomeScreen at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildHomeScreen(entry.value),
          entry.value,
        );
      });

      testWidgets('TripDashboard at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildScreen(TripDashboardScreen(tripId: tripId), entry.value),
          entry.value,
        );
      });

      testWidgets('PeopleScreen at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildScreen(PeopleScreen(tripId: tripId), entry.value),
          entry.value,
        );
      });

      testWidgets('BalancesScreen at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildScreen(BalancesScreen(tripId: tripId), entry.value),
          entry.value,
        );
      });

      testWidgets('SettlementsScreen at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildScreen(SettlementsScreen(tripId: tripId), entry.value),
          entry.value,
        );
      });

      testWidgets('ExpenseManagementScreen at ${entry.key}', (tester) async {
        await assertNoOverflow(
          tester,
          buildScreen(ExpenseManagementScreen(tripId: tripId), entry.value),
          entry.value,
        );
      });
    }
  });

  group('Large text scale (390x844, scale 1.3)', () {
    Future<void> assertNoOverflowWithTextScale(
      WidgetTester tester,
      Widget app,
    ) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isNull, reason: 'Unexpected exception at 1.3x text scale');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('HomeScreen at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildHomeScreen(const BoxConstraints.expand(width: 390, height: 844)),
      );
    });

    testWidgets('TripDashboard at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildScreen(
          TripDashboardScreen(tripId: tripId),
          const BoxConstraints.expand(width: 390, height: 844),
        ),
      );
    });

    testWidgets('PeopleScreen at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildScreen(
          PeopleScreen(tripId: tripId),
          const BoxConstraints.expand(width: 390, height: 844),
        ),
      );
    });

    testWidgets('BalancesScreen at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildScreen(
          BalancesScreen(tripId: tripId),
          const BoxConstraints.expand(width: 390, height: 844),
        ),
      );
    });

    testWidgets('SettlementsScreen at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildScreen(
          SettlementsScreen(tripId: tripId),
          const BoxConstraints.expand(width: 390, height: 844),
        ),
      );
    });

    testWidgets('ExpenseManagementScreen at 1.3x text scale', (tester) async {
      await assertNoOverflowWithTextScale(
        tester,
        buildScreen(
          ExpenseManagementScreen(tripId: tripId),
          const BoxConstraints.expand(width: 390, height: 844),
        ),
      );
    });
  });
}
