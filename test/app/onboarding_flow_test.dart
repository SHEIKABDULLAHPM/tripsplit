import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripsplit/app/app.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Covers the complete first-launch journey: Splash → Welcome → the three-step
/// onboarding tour → Home, plus the "skip" short-circuit.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(
            AppDatabase.forTesting(NativeDatabase.memory()),
          ),
        ],
        child: const TripSplitApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new user walks splash → welcome → onboarding → home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpApp(tester);

    // 1. Welcome (splash auto-routed after the minimum hold).
    expect(find.text('Every rupee, accounted for.'), findsOneWidget);

    // 2. Start the tour.
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the budget'), findsOneWidget);

    // 3. Advance through all pages.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Split expenses fairly'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Settle up, offline'), findsOneWidget);

    // 4. Finish → home.
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);

    // The completion flag must be persisted for the next launch.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('welcome "Skip tour" jumps straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpApp(tester);

    expect(find.text('Every rupee, accounted for.'), findsOneWidget);
    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);
  });

  testWidgets('onboarding "Skip" also completes onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpApp(tester);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the budget'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('returning user never sees onboarding again', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await pumpApp(tester);

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Every rupee, accounted for.'), findsNothing);
    expect(find.text('Plan the budget'), findsNothing);
  });
}
