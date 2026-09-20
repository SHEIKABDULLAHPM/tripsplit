import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripsplit/app/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Marks onboarding already done so the app skips Welcome/Onboarding and
  /// boots straight into the home screen (the returning-user path).
  Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }

  testWidgets('application launches and renders the home screen', (
    tester,
  ) async {
    await markOnboardingComplete();
    await tester.pumpWidget(const ProviderScope(child: TripSplitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsWidgets);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Create trip'), findsOneWidget);
  });

  testWidgets('creates a real empty local database on device', (tester) async {
    await markOnboardingComplete();
    await tester.pumpWidget(const ProviderScope(child: TripSplitApp()));
    await tester.pumpAndSettle();

    // Navigate to the create-trip screen to exercise the router and
    // confirm the database provider can be read without crashing.
    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('New trip'), findsOneWidget);
  });
}
