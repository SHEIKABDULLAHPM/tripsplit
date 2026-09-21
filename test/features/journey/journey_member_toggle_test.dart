import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/journey/data/journey_repository_impl.dart';
import 'package:tripsplit/features/journey/domain/journey_repository.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';

/// Regression tests for journey member on/off toggle behavior.
///
/// Verifies that:
/// - Enabling/disabling members persists correctly.
/// - Rapid toggles don't corrupt state.
/// - Member selection is consistent across screens.
/// - Unrelated data (expenses, settlements) is not affected by toggle changes.
void main() {
  group('Journey member toggle regression', () {
    late AppDatabase db;
    late JourneyRepository journeyRepository;
    late TeamRepository teamRepository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      journeyRepository = JourneyRepositoryImpl(db);
      teamRepository = TeamRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<(int tripId, List<int> memberIds)> seedTripWithMembers(
      List<String> names,
    ) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Trip'),
      );
      final ids = <int>[];
      for (final name in names) {
        ids.add(
          await db.memberDao.insert(
            MembersCompanion.insert(tripId: tripId, name: name),
          ),
        );
      }
      return (tripId, ids);
    }

    Future<int> seedLocation(int tripId, String name) async {
      final loc = await journeyRepository.addLocation(tripId, name);
      return loc.id;
    }

    Future<int> seedSegment(int tripId, int startId, int endId) async {
      await journeyRepository.addSegment(
        tripId,
        startLocationId: startId,
        endLocationId: endId,
      );
      final segments = await journeyRepository.getSegments(tripId);
      return segments.last.id;
    }

    // ── Scenario 1: Enable a member ──────────────────────────────────────

    test('Scenario 1: Enable a member for a segment', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Disable B from the segment.
      await journeyRepository.setParticipation(
        memberId: ids[1],
        segmentId: segId,
        participating: false,
      );

      var parts = await journeyRepository.getParticipations(tripId);
      final bPart = parts.firstWhere(
        (p) => p.memberId == ids[1] && p.segmentId == segId,
      );
      expect(bPart.participating, isFalse);

      // Re-enable B.
      await journeyRepository.setParticipation(
        memberId: ids[1],
        segmentId: segId,
        participating: true,
      );

      parts = await journeyRepository.getParticipations(tripId);
      final bPartAfter = parts.firstWhere(
        (p) => p.memberId == ids[1] && p.segmentId == segId,
      );
      expect(bPartAfter.participating, isTrue);
    });

    // ── Scenario 2: Disable a member ─────────────────────────────────────

    test('Scenario 2: Disable a member from a segment', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Initially all members participate (default).
      var parts = await journeyRepository.getParticipations(tripId);
      expect(parts.any((p) => p.memberId == ids[0] && p.participating), isTrue);

      // Disable A.
      await journeyRepository.setParticipation(
        memberId: ids[0],
        segmentId: segId,
        participating: false,
      );

      parts = await journeyRepository.getParticipations(tripId);
      final aPart = parts.firstWhere(
        (p) => p.memberId == ids[0] && p.segmentId == segId,
      );
      expect(aPart.participating, isFalse);
    });

    // ── Scenario 3: Rapidly toggle multiple members ──────────────────────

    test('Scenario 3: Rapidly toggle multiple members', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Rapidly toggle B, C, D in sequence.
      await journeyRepository.setParticipation(
        memberId: ids[1],
        segmentId: segId,
        participating: false,
      );
      await journeyRepository.setParticipation(
        memberId: ids[2],
        segmentId: segId,
        participating: false,
      );
      await journeyRepository.setParticipation(
        memberId: ids[3],
        segmentId: segId,
        participating: false,
      );

      var parts = await journeyRepository.getParticipations(tripId);
      // Only A should still be participating.
      for (final id in [ids[1], ids[2], ids[3]]) {
        final part = parts.firstWhere(
          (p) => p.memberId == id && p.segmentId == segId,
        );
        expect(part.participating, isFalse);
      }

      // Toggle B and C back on.
      await journeyRepository.setParticipation(
        memberId: ids[1],
        segmentId: segId,
        participating: true,
      );
      await journeyRepository.setParticipation(
        memberId: ids[2],
        segmentId: segId,
        participating: true,
      );

      parts = await journeyRepository.getParticipations(tripId);
      final aPart = parts.firstWhere(
        (p) => p.memberId == ids[0] && p.segmentId == segId,
      );
      expect(aPart.participating, isTrue);

      final bPart = parts.firstWhere(
        (p) => p.memberId == ids[1] && p.segmentId == segId,
      );
      expect(bPart.participating, isTrue);

      final cPart = parts.firstWhere(
        (p) => p.memberId == ids[2] && p.segmentId == segId,
      );
      expect(cPart.participating, isTrue);

      final dPart = parts.firstWhere(
        (p) => p.memberId == ids[3] && p.segmentId == segId,
      );
      expect(dPart.participating, isFalse);
    });

    // ── Scenario 4: Navigate away and return ─────────────────────────────

    test('Scenario 4: Participation persists across re-reads', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Disable A.
      await journeyRepository.setParticipation(
        memberId: ids[0],
        segmentId: segId,
        participating: false,
      );

      // "Navigate away" by re-reading participations.
      final parts = await journeyRepository.getParticipations(tripId);
      final aPart = parts.firstWhere(
        (p) => p.memberId == ids[0] && p.segmentId == segId,
      );
      expect(aPart.participating, isFalse);

      // Also verify via stream.
      final streamParts = await journeyRepository
          .watchParticipations(tripId)
          .first;
      final aPartStream = streamParts.firstWhere(
        (p) => p.memberId == ids[0] && p.segmentId == segId,
      );
      expect(aPartStream.participating, isFalse);
    });

    // ── Scenario 5: Switch between Journey, Teams, Expenses, etc. ────────

    test('Scenario 5: Toggle state consistent across repositories', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Toggle A off.
      await journeyRepository.setParticipation(
        memberId: ids[0],
        segmentId: segId,
        participating: false,
      );

      // Verify via journey repository.
      final journeyParts = await journeyRepository.getParticipations(tripId);
      expect(
        journeyParts
            .where((p) => p.memberId == ids[0] && p.segmentId == segId)
            .every((p) => !p.participating),
        isTrue,
      );

      // Verify via team repository (members still belong to teams).
      final team = await teamRepository.createTeam(tripId, 'Team 1');
      await teamRepository.addMember(teamId: team.id, memberId: ids[0]);
      await teamRepository.addMember(teamId: team.id, memberId: ids[1]);
      final teamMembers = await teamRepository.getTeamMembers(team.id);
      expect(teamMembers, hasLength(2));

      // The journey toggle does not affect team membership.
    });

    // ── Scenario 6: Selected member state remains correct ────────────────

    test('Scenario 6: Selected state is durable', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Toggle B off.
      await journeyRepository.setParticipation(
        memberId: ids[1],
        segmentId: segId,
        participating: false,
      );

      // Read multiple times to simulate navigating between screens.
      for (var i = 0; i < 5; i++) {
        final parts = await journeyRepository.getParticipations(tripId);
        final bPart = parts.firstWhere(
          (p) => p.memberId == ids[1] && p.segmentId == segId,
        );
        expect(
          bPart.participating,
          isFalse,
          reason: 'State drifted on read $i',
        );
      }
    });

    // ── Scenario 7: Unrelated data not reloaded ──────────────────────────

    test(
      'Scenario 7: Team membership unaffected by participation toggle',
      () async {
        final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);
        final loc1 = await seedLocation(tripId, 'Erode');
        final loc2 = await seedLocation(tripId, 'Salem');
        final segId = await seedSegment(tripId, loc1, loc2);

        // Set up a team.
        final team = await teamRepository.createTeam(tripId, 'Team 1');
        await teamRepository.addMember(teamId: team.id, memberId: ids[0]);
        await teamRepository.addMember(teamId: team.id, memberId: ids[1]);

        final before = await teamRepository.getTeamMembers(team.id);
        expect(before, hasLength(2));

        // Toggle participation.
        await journeyRepository.setParticipation(
          memberId: ids[0],
          segmentId: segId,
          participating: false,
        );

        // Team membership is unchanged.
        final after = await teamRepository.getTeamMembers(team.id);
        expect(after, hasLength(2));
      },
    );

    // ── Scenario 8: Existing expenses/settlements not corrupted ──────────

    test('Scenario 8: Participation toggle does not affect expenses', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final loc1 = await seedLocation(tripId, 'Erode');
      final loc2 = await seedLocation(tripId, 'Salem');
      final segId = await seedSegment(tripId, loc1, loc2);

      // Create an expense before toggling participation.
      final expenseId = await db.expenseDao.insert(
        ExpensesCompanion(
          tripId: Value(tripId),
          payerMemberId: Value(ids[0]),
          description: const Value('Food'),
          amountMinor: const Value(100_00),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await db.expenseDao.insertShare(
        ExpenseSharesCompanion(
          expenseId: Value(expenseId),
          memberId: Value(ids[0]),
          shareMinor: const Value(50_00),
        ),
      );
      await db.expenseDao.insertShare(
        ExpenseSharesCompanion(
          expenseId: Value(expenseId),
          memberId: Value(ids[1]),
          shareMinor: const Value(50_00),
        ),
      );
      await db.journeyDao.insertPayment(
        ExpensePaymentsCompanion(
          expenseId: Value(expenseId),
          memberId: Value(ids[0]),
          amountMinor: const Value(100_00),
        ),
      );

      // Verify expense exists.
      final expenses = await db.expenseDao.getByTrip(tripId);
      expect(expenses, hasLength(1));
      expect(expenses.first.amountMinor, 100_00);

      // Toggle participation.
      await journeyRepository.setParticipation(
        memberId: ids[0],
        segmentId: segId,
        participating: false,
      );

      // Expense and its shares are unchanged.
      final expensesAfter = await db.expenseDao.getByTrip(tripId);
      expect(expensesAfter, hasLength(1));
      expect(expensesAfter.first.amountMinor, 100_00);

      final shares = await db.expenseDao.getSharesFor(expenseId);
      expect(shares, hasLength(2));
    });
  });
}
