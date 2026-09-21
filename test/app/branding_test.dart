import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tripsplit/app/screens/welcome_screen.dart';
import 'package:tripsplit/app/theme/app_theme.dart';
import 'package:tripsplit/app/widgets/brand_lockup.dart';
import 'package:tripsplit/app/widgets/help_support_popup.dart';
import 'package:tripsplit/app/widgets/home_screen.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Reports the Help & Support popup as already shown.
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

  testWidgets('home app bar presents the brand mark at a prominent size', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          helpSupportPopupFlagProvider.overrideWith(
            _ShownHelpSupportPopupFlag.new,
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final mark = tester.widget<TripSplitMark>(find.byType(TripSplitMark));
    expect(mark.size, 36);
  });

  testWidgets('brand lockups scale each size to a balanced, larger mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              BrandLockup(size: BrandLockupSize.small),
              BrandLockup(size: BrandLockupSize.medium),
              BrandLockup(size: BrandLockupSize.hero),
            ],
          ),
        ),
      ),
    );

    final marks = tester
        .widgetList<TripSplitMark>(find.byType(TripSplitMark))
        .toList();
    expect(marks, hasLength(3));
    expect(marks.map((m) => m.size).toList(), [26, 44, 56]);
  });

  testWidgets('welcome screen renders the medium brand lockup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const WelcomeScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BrandLockup), findsOneWidget);
    final lockup = tester.widget<BrandLockup>(find.byType(BrandLockup));
    expect(lockup.size, BrandLockupSize.medium);
  });
}
