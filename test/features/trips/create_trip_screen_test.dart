import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/trips/presentation/create_trip_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget app() => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CreateTripScreen()),
  );

  Future<void> openMembers(WidgetTester tester) async {
    await tester.tap(find.text('Add members'));
    await tester.pumpAndSettle();
  }

  testWidgets('rejects a negative member contribution without crashing', (
    tester,
  ) async {
    await useTallSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Trip name'),
      'Goa',
    );
    await openMembers(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Suganth',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contribution'),
      '-100',
    );
    await tester.pump();

    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('Contribution cannot be negative.'), findsOneWidget);
    expect(await db.tripDao.getAll(), isEmpty);
  });

  testWidgets('rejects an unparseable member contribution without crashing', (
    tester,
  ) async {
    await useTallSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Trip name'),
      'Goa',
    );
    await openMembers(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Suganth',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contribution'),
      'abc',
    );
    await tester.pump();

    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount.'), findsOneWidget);
    expect(await db.tripDao.getAll(), isEmpty);
  });

  testWidgets('rejects a negative planned budget without crashing', (
    tester,
  ) async {
    await useTallSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Trip name'),
      'Goa',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Planned group budget'),
      '-1',
    );
    await openMembers(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Suganth',
    );
    await tester.pump();

    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('Budget cannot be negative.'), findsWidgets);
    expect(await db.tripDao.getAll(), isEmpty);
  });
}
