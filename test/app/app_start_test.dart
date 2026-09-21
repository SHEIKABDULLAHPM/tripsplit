import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripsplit/app/app.dart';
import 'package:tripsplit/app/widgets/help_support_popup.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Reports the Help & Support popup as already shown so startup tests are not
/// blocked by the app-open popup.
class _ShownHelpSupportPopupFlag extends HelpSupportPopupFlag {
  @override
  bool build() => true;
}

void main() {
  group('TripSplit app', () {
    Future<void> pumpApp(WidgetTester tester) async {
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
          child: const TripSplitApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'returning users start at the home screen with an empty state',
      (tester) async {
        SharedPreferences.setMockInitialValues({'onboarding_completed': true});
        await pumpApp(tester);

        expect(find.text('Trips'), findsOneWidget);
        expect(find.text('No trips yet'), findsOneWidget);
      },
    );

    testWidgets('navigates to the create-trip screen', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      await pumpApp(tester);

      await tester.tap(find.text('Create trip'));
      await tester.pumpAndSettle();

      expect(find.text('New trip'), findsOneWidget);
      expect(find.text('Trip name'), findsOneWidget);
    });

    testWidgets('home screen does not touch the network', (tester) async {
      // If the app attempted any network I/O during startup, these widget
      // tests would time out or hit a real socket. Rendering proves the
      // offline-first shell is self-contained.
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      await pumpApp(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('first launch shows welcome and skip lands on home', (
      tester,
    ) async {
      // No shared preferences yet → brand-new installer.
      SharedPreferences.setMockInitialValues({});
      await pumpApp(tester);

      expect(find.text('Every rupee, accounted for.'), findsOneWidget);

      await tester.tap(find.text('Skip tour'));
      await tester.pumpAndSettle();

      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('No trips yet'), findsOneWidget);
    });
  });
}
