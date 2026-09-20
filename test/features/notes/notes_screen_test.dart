import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/notes/presentation/notes_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  Future<int> seedTrip([String name = 'Goa']) =>
      db.tripDao.insert(TripsCompanion.insert(name: name));

  Widget app(int tripId) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: NotesScreen(tripId: tripId)),
  );

  /// Unmounts the screen and lets the Drift query stream finish its shutdown
  /// timer so no pending timers are reported at the end of the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the empty state for a trip without notes', (tester) async {
    final tripId = await seedTrip();
    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Quick note'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('persists a note scoped to the trip', (tester) async {
    final tripId = await seedTrip();
    await tester.pumpWidget(app(tripId));
    await tester.pump(const Duration(milliseconds: 100));

    // A focused text field blinks its cursor forever, so pumpAndSettle would
    // never finish while the editor is open. Pump explicit durations instead.
    await tester.tap(find.text('Quick note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byType(TextField),
      'Keep the return tickets handy.',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The first sentence becomes the auto-generated title; the full body is
    // shown in the card subtitle.
    expect(find.text('Keep the return tickets handy'), findsOneWidget);
    expect(find.text('Keep the return tickets handy.'), findsOneWidget);

    final notes = await db.noteDao.getByTrip(tripId);
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Keep the return tickets handy');
    expect(notes.single.body, 'Keep the return tickets handy.');
    expect(notes.single.tripId, tripId);

    await unmount(tester);
  });

  testWidgets("keeps each trip's notes separate", (tester) async {
    final firstTripId = await seedTrip('Kerala');
    final secondTripId = await seedTrip('Goa');

    await db.noteDao.insert(
      NotesCompanion.insert(tripId: firstTripId, title: 'First trip note'),
    );

    await tester.pumpWidget(app(secondTripId));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('First trip note'), findsNothing);

    await unmount(tester);
  });

  testWidgets('deletes a note', (tester) async {
    final tripId = await seedTrip();
    await db.noteDao.insert(
      NotesCompanion.insert(tripId: tripId, title: 'Packing'),
    );

    await tester.pumpWidget(app(tripId));
    await tester.pumpAndSettle();
    expect(find.text('Packing'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Packing'), findsNothing);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(await db.noteDao.getByTrip(tripId), isEmpty);

    await unmount(tester);
  });
}
