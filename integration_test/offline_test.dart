import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripsplit/app/app.dart';

/// Fails the app instantly on any socket creation, proving the app never
/// depends on network access for its core flow.
class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('Network access is disabled in offline test.');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app works fully offline', (tester) async {
    HttpOverrides.global = _OfflineHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    await tester.pumpWidget(const ProviderScope(child: TripSplitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsWidgets);
    expect(find.text('No trips yet'), findsOneWidget);

    // Navigate through the new-trip flow with networking blocked.
    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();
    expect(find.text('New trip'), findsOneWidget);
    expect(find.text('Trip name'), findsOneWidget);
  });
}
