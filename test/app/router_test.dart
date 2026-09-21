import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripsplit/app/router.dart';
import 'package:tripsplit/app/widgets/help_support_popup.dart';
import 'package:tripsplit/app/widgets/home_screen.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Reports the Help & Support popup as already shown so these navigation
/// tests are not blocked by the app-open popup.
class _ShownHelpSupportPopupFlag extends HelpSupportPopupFlag {
  @override
  bool build() => true;
}

void main() {
  group('AppRouter', () {
    late GoRouter router;

    setUp(() {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      router = AppRouter.create();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(
              AppDatabase.forTesting(NativeDatabase.memory()),
            ),
            helpSupportPopupFlagProvider.overrideWith(
              _ShownHelpSupportPopupFlag.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('starts at splash and settles on home', (tester) async {
      expect(AppRoutes.splash, '/splash');
      await pump(tester);

      expect(router.state.matchedLocation, AppRoutes.home);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('navigates between registered routes', (tester) async {
      await pump(tester);

      router.go(AppRoutes.createTrip);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, AppRoutes.createTrip);

      router.go(AppRoutes.trip(7));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, AppRoutes.trip(7));
    });

    testWidgets('exposes helpers for sub-routes', (tester) async {
      await pump(tester);

      expect(AppRoutes.people(3), '/trip/3/members');
      expect(AppRoutes.addMember(3), '/trip/3/members/new');
      expect(AppRoutes.addContribution(3), '/trip/3/contributions/new');
      expect(AppRoutes.expenses(3), '/trip/3/expenses');
      expect(AppRoutes.addExpense(3), '/trip/3/expenses/new');
      expect(
        AppRoutes.addExpense(3, segmentId: 5),
        '/trip/3/expenses/new?segmentId=5',
      );
      expect(
        AppRoutes.addExpense(3, teamId: 2),
        '/trip/3/expenses/new?teamId=2',
      );
      expect(
        AppRoutes.addExpense(3, payerMemberId: 4),
        '/trip/3/expenses/new?payerId=4',
      );
      expect(
        AppRoutes.addExpense(3, segmentId: 5, teamId: 2, payerMemberId: 4),
        '/trip/3/expenses/new?segmentId=5&teamId=2&payerId=4',
      );
      expect(AppRoutes.memberDetail(3, 7), '/trip/3/members/7');
      expect(AppRoutes.expense(3, 9), '/trip/3/expenses/9');
      expect(AppRoutes.editExpense(3, 9), '/trip/3/expenses/9/edit');
      expect(AppRoutes.balances(3), '/trip/3/balances');
      expect(AppRoutes.settlements(3), '/trip/3/settlements');
      expect(AppRoutes.recordSettlement(3), '/trip/3/settlements/new');
    });

    testWidgets('funding is reachable from a trip More tab and backs out', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.closeDatabase);
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Test Trip'),
      );

      final router = AppRouter.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            helpSupportPopupFlagProvider.overrideWith(
              _ShownHelpSupportPopupFlag.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.trip(tripId));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Support TripSplit'), findsOneWidget);
      await tester.tap(find.text('Support TripSplit'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, AppRoutes.funding);
      expect(find.text('Support Funding'), findsOneWidget);
      expect(find.text('Future Funding'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, AppRoutes.more(tripId));
    });

    testWidgets('funding stays reachable from the home overflow menu', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support TripSplit'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, AppRoutes.funding);
      expect(find.text('Support Funding'), findsOneWidget);
    });
  });
}
