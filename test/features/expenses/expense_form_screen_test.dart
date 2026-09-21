import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/presentation/expense_form_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  /// The form is a scrollable ListView; enlarge the test surface so fields and
  /// the save button are all built without scrolling.
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<int> seedTripWithMembers() async {
    final tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'Goa'));
    await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Suganth'),
    );
    await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Man'),
    );
    return tripId;
  }

  Widget app(int tripId) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: ExpenseFormScreen.create(tripId: tripId)),
  );

  /// Unmounts the screen and lets the Drift query stream finish its shutdown
  /// timer so no pending timers are reported at the end of the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('split preview shares only the group amount and shows external', (
    tester,
  ) async {
    await useTallSurface(tester);
    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    // Description (0) is skipped; amount (1) and external (2) are filled.
    await tester.enterText(find.byType(TextFormField).at(1), '730.90');
    await tester.enterText(find.byType(TextFormField).at(2), '365.50');
    await tester.pump();

    // Total (split) = 730.90 - 365.50 = 365.40, split two ways.
    expect(find.text('Total (split)'), findsOneWidget);
    expect(find.text('₹365.40'), findsOneWidget);
    expect(find.text('External (not shared)'), findsOneWidget);
    expect(find.text('₹365.50'), findsOneWidget);
    expect(find.text('Paid by the payer'), findsOneWidget);
    expect(find.text('₹730.90'), findsOneWidget);

    // Each participant should show a 182.70 share (365.40 / 2).
    expect(find.text('₹182.70'), findsNWidgets(2));

    await unmount(tester);
  });

  testWidgets('rejects an external portion that consumes the whole amount', (
    tester,
  ) async {
    await useTallSurface(tester);
    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '10.00');
    await tester.enterText(find.byType(TextFormField).at(2), '10.00');
    await tester.pump();

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Must be smaller than the amount so some of the expense is shared.',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('rejects a negative external portion', (tester) async {
    await useTallSurface(tester);
    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '730.90');
    await tester.enterText(find.byType(TextFormField).at(2), '-1');
    await tester.pump();

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('custom share inputs do not crash when a participant is '
      'toggled on after selecting Custom scope', (tester) async {
    await useTallSurface(tester);
    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    // Switch to Custom scope: this clears participants, so the share inputs
    // rebuild with an empty participant list.
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    // Toggle a member's FilterChip on. Previously this new participant had no
    // TextEditingController in _CustomShareInputs and didUpdateWidget crashed
    // with a null-check error.
    await tester.tap(find.widgetWithText(FilterChip, 'Suganth'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter share for each participant'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('other-payer rows do not overflow on narrow screens', (
    tester,
  ) async {
    // A narrow phone surface; previously the "Who paid" dropdown in each
    // "Other people who paid" row overflowed its flex slot by up to ~27px.
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Advanced options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another payer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '3288.60');
    await tester.pump();

    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('"Who paid" label and its selected text use visible themed '
      'colors', (tester) async {
    await useTallSurface(tester);
    final tripId = await seedTripWithMembers();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Advanced options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another payer'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ExpenseFormScreen));
    final scheme = Theme.of(context).colorScheme;

    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.ancestor(
        of: find.text('Who paid'),
        matching: find.byType(DropdownButtonFormField<int>),
      ),
    );
    final visibleOnSurface = scheme.onSurfaceVariant;
    expect(dropdown.decoration.labelStyle?.color, visibleOnSurface);
    expect(dropdown.decoration.labelStyle?.color, isNot(Colors.white));

    // The selected payer value renders in the base text color — never white.
    final selectedText = tester.element(find.text('Suganth').first);
    final selectedColor = DefaultTextStyle.of(selectedText).style.color;
    expect(selectedColor, isNot(Colors.white));

    await unmount(tester);
  });
}
