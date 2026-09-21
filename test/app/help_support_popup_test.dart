import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tripsplit/app/theme/app_theme.dart';
import 'package:tripsplit/app/widgets/help_support_popup.dart';
import 'package:tripsplit/app/widgets/home_screen.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Reports the Help & Support popup as already shown (used to probe the
/// no-duplicate guarantee).
class _ShownHelpSupportPopupFlag extends HelpSupportPopupFlag {
  @override
  bool build() => true;
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  Widget mount({bool suppress = false}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (suppress)
        helpSupportPopupFlagProvider.overrideWith(
          _ShownHelpSupportPopupFlag.new,
        ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
  );

  testWidgets('shows the Help & Support popup when the app opens', (
    tester,
  ) async {
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();

    expect(find.byType(HelpSupportPopup), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Support the project'), findsOneWidget);
  });

  testWidgets('closes cleanly and leaves Home usable after dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpSupportPopup), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Create trip'), findsOneWidget);
  });

  testWidgets('does not duplicate the popup within one session', (
    tester,
  ) async {
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();
    expect(find.byType(HelpSupportPopup), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpSupportPopup), findsNothing);

    // Re-mounting Home in the same session must not re-show it.
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();

    expect(find.byType(HelpSupportPopup), findsNothing);
  });

  testWidgets('renders without overflow on a small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();

    expect(find.byType(HelpSupportPopup), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can be suppressed via the session flag override', (
    tester,
  ) async {
    await tester.pumpWidget(mount(suppress: true));
    await tester.pumpAndSettle();

    expect(find.byType(HelpSupportPopup), findsNothing);
  });
}
