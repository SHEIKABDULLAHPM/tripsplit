import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/journey/data/journey_repository_impl.dart';
import 'package:tripsplit/features/journey/domain/journey_repository.dart';

void main() {
  group('JourneyRepositoryImpl', () {
    late AppDatabase db;
    late JourneyRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = JourneyRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<(int tripId, int memberA, int memberB)> seed(
      List<String> locationNames,
    ) async {
      final tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'T'));
      final memberA = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'A'),
      );
      final memberB = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'B'),
      );
      for (final name in locationNames) {
        await repository.addLocation(tripId, name);
      }
      return (tripId, memberA, memberB);
    }

    test('addSegment derives default participation for every member', () async {
      final (tripId, memberA, memberB) = await seed(['Erode', 'Salem']);
      final locations = await repository.getLocations(tripId);

      await repository.addSegment(
        tripId,
        startLocationId: locations[0].id,
        endLocationId: locations[1].id,
      );

      final segments = await repository.getSegments(tripId);
      expect(segments, hasLength(1));

      final participations = await repository.getParticipations(tripId);
      expect(participations, hasLength(2));
      final ids = {participations[0].memberId, participations[1].memberId};
      expect(ids, {memberA, memberB});
      expect(participations.every((p) => p.participating), isTrue);
    });

    test(
      'explicit override survives, resequence keeps route connected',
      () async {
        final (tripId, memberA, _) = await seed([
          'Erode',
          'Salem',
          'Bengaluru',
        ]);
        final locations = await repository.getLocations(tripId);
        // Loop route Erode→Salem→Bengaluru→Erode so a reorder can stay
        // connected.
        await repository.addSegment(
          tripId,
          startLocationId: locations[0].id,
          endLocationId: locations[1].id,
        );
        await repository.addSegment(
          tripId,
          startLocationId: locations[1].id,
          endLocationId: locations[2].id,
        );
        await repository.addSegment(
          tripId,
          startLocationId: locations[2].id,
          endLocationId: locations[0].id,
        );
        final segments = await repository.getSegments(tripId);

        await repository.setParticipation(
          memberId: memberA,
          segmentId: segments[0].id,
          participating: false,
        );

        await repository.resequenceSegments([
          segments[1].id,
          segments[2].id,
          segments[0].id,
        ]);

        final resequenced = await repository.getSegments(tripId);
        expect(resequenced.map((s) => s.sequence), [0, 1, 2]);
        // Route stays connected: each segment starts where the previous ends.
        for (var i = 0; i < resequenced.length - 1; i++) {
          expect(
            resequenced[i].endLocationId,
            resequenced[i + 1].startLocationId,
          );
        }

        final overrides = await repository.getParticipations(tripId);
        final kept = overrides.firstWhere(
          (p) => p.memberId == memberA && p.segmentId == segments[0].id,
        );
        expect(kept.participating, isFalse);
      },
    );

    test('deleteSegment clears participation rows for that segment', () async {
      final (tripId, _, _) = await seed(['Erode', 'Salem', 'Bengaluru']);
      final locations = await repository.getLocations(tripId);
      await repository.addSegment(
        tripId,
        startLocationId: locations[0].id,
        endLocationId: locations[1].id,
      );
      await repository.addSegment(
        tripId,
        startLocationId: locations[1].id,
        endLocationId: locations[2].id,
      );
      final segments = await repository.getSegments(tripId);

      await repository.deleteSegment(segments[0].id);

      final remaining = await repository.getSegments(tripId);
      expect(remaining.map((s) => s.id), [segments[1].id]);
      final participations = await repository.getParticipations(tripId);
      expect(
        participations.every((p) => p.segmentId != segments[0].id),
        isTrue,
      );
      expect(participations, isNotEmpty);
    });
  });
}
