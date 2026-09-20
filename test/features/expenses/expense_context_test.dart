import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/app/router.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
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

  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Unmounts the screen and lets the Drift query stream finish its shutdown
  /// timer so no pending timers are reported at the end of the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Seeds a trip with members, journey locations, segments,
  /// and a team for testing context-aware form initialization.
  Future<_SeedData> seedFullTrip() async {
    final tripId = await db.tripDao.insert(
      TripsCompanion.insert(
        name: 'Test Trip',
        startLocation: const Value('Erode'),
      ),
    );

    // Members
    final dharId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Dhar'),
    );
    final gowthamId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Gowtham'),
    );
    final sanuId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Sanu'),
    );
    final mowliId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Mowli'),
    );

    // Locations
    final erodeId = await db.journeyDao.insertLocation(
      LocationsCompanion.insert(tripId: tripId, name: 'Erode'),
    );
    final salemId = await db.journeyDao.insertLocation(
      LocationsCompanion.insert(tripId: tripId, name: 'Salem'),
    );
    final bengaluruId = await db.journeyDao.insertLocation(
      LocationsCompanion.insert(tripId: tripId, name: 'Bengaluru'),
    );

    // Segments (insertSegment returns void, so we query for IDs)
    await db.journeyDao.insertSegment(
      TravelSegmentsCompanion.insert(
        tripId: tripId,
        sequence: 0,
        startLocationId: erodeId,
        endLocationId: salemId,
      ),
    );
    await db.journeyDao.insertSegment(
      TravelSegmentsCompanion.insert(
        tripId: tripId,
        sequence: 1,
        startLocationId: salemId,
        endLocationId: bengaluruId,
      ),
    );
    final segments = await db.journeyDao.getSegments(tripId);
    final seg1Id = segments[0].id;
    final seg2Id = segments[1].id;

    // Team
    final teamId = await db.journeyDao.insertTeam(
      TeamsCompanion.insert(tripId: tripId, name: 'Car 1'),
    );
    await db.journeyDao.addTeamMember(teamId, dharId);
    await db.journeyDao.addTeamMember(teamId, gowthamId);

    return _SeedData(
      tripId: tripId,
      dharId: dharId,
      gowthamId: gowthamId,
      sanuId: sanuId,
      mowliId: mowliId,
      seg1Id: seg1Id,
      seg2Id: seg2Id,
      teamId: teamId,
    );
  }

  group('ExpenseFormScreen context-aware initialization', () {
    testWidgets('applies segment context and pre-selects Segment scope', (
      tester,
    ) async {
      await useTallSurface(tester);
      final data = await seedFullTrip();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: ExpenseFormScreen.create(
              tripId: data.tripId,
              initialSegmentId: data.seg1Id,
            ),
          ),
        ),
      );
      // Allow the StreamProvider to emit its first value
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // The "Segment" scope button should be selected
      expect(find.text('Segment'), findsOneWidget);

      // The segment picker should be visible
      expect(find.text('Travel segment'), findsWidgets);

      await unmount(tester);
    });

    testWidgets('applies team context and pre-selects Team scope', (
      tester,
    ) async {
      await useTallSurface(tester);
      final data = await seedFullTrip();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: ExpenseFormScreen.create(
              tripId: data.tripId,
              initialTeamId: data.teamId,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // The "Team" scope button should be selected
      expect(find.text('Team'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('no context keeps Shared scope as default', (tester) async {
      await useTallSurface(tester);
      final data = await seedFullTrip();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: ExpenseFormScreen.create(tripId: data.tripId),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // "Shared" should be the default scope
      expect(find.text('Shared'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('edit mode loads existing expense data', (tester) async {
      await useTallSurface(tester);
      final data = await seedFullTrip();

      // Create an expense first
      final repo = ExpenseRepositoryImpl(db);
      await repo.createExpense(
        tripId: data.tripId,
        description: 'Train to Salem',
        amountMinor: 40000,
        payerMemberId: data.dharId,
        participantMemberIds: [data.dharId, data.gowthamId, data.mowliId],
      );

      final expenses = await repo.getByTrip(data.tripId);
      final expenseId = expenses.first.id;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: ExpenseFormScreen.edit(
              tripId: data.tripId,
              expenseId: expenseId,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // The expense description should be loaded
      expect(find.text('Train to Salem'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('Router context-aware URL generation', () {
    test('generates plain URL when no context provided', () {
      expect(AppRoutes.addExpense(1), '/trip/1/expenses/new');
    });

    test('generates URL with segmentId', () {
      expect(
        AppRoutes.addExpense(1, segmentId: 5),
        '/trip/1/expenses/new?segmentId=5',
      );
    });

    test('generates URL with teamId', () {
      expect(
        AppRoutes.addExpense(1, teamId: 2),
        '/trip/1/expenses/new?teamId=2',
      );
    });

    test('generates URL with payerMemberId', () {
      expect(
        AppRoutes.addExpense(1, payerMemberId: 3),
        '/trip/1/expenses/new?payerId=3',
      );
    });

    test('generates URL with all context parameters', () {
      expect(
        AppRoutes.addExpense(1, segmentId: 5, teamId: 2, payerMemberId: 3),
        '/trip/1/expenses/new?segmentId=5&teamId=2&payerId=3',
      );
    });

    test('generates member detail URL', () {
      expect(AppRoutes.memberDetail(1, 7), '/trip/1/members/7');
    });
  });
}

class _SeedData {
  const _SeedData({
    required this.tripId,
    required this.dharId,
    required this.gowthamId,
    required this.sanuId,
    required this.mowliId,
    required this.seg1Id,
    required this.seg2Id,
    required this.teamId,
  });

  final int tripId;
  final int dharId;
  final int gowthamId;
  final int sanuId;
  final int mowliId;
  final int seg1Id;
  final int seg2Id;
  final int teamId;
}
