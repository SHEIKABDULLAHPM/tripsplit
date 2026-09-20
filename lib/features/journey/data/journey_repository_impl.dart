import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../../core/calculations/participation.dart';
import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/journey.dart';
import '../domain/journey_repository.dart';

/// Drift-backed [JourneyRepository].
class JourneyRepositoryImpl implements JourneyRepository {
  JourneyRepositoryImpl(this._db);

  final AppDatabase _db;

  // -- Locations ---------------------------------------------------------------

  @override
  Stream<List<TripLocation>> watchLocations(int tripId) => _db.journeyDao
      .watchLocations(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<TripLocation>> getLocations(int tripId) async =>
      (await _db.journeyDao.getLocations(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<TripLocation> addLocation(int tripId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('A location needs a name.');
    }
    if (trimmed.length > 80) {
      throw const ValidationException(
        'The location name must be 80 characters or fewer.',
      );
    }
    try {
      final id = await _db.journeyDao.insertLocation(
        LocationsCompanion.insert(tripId: tripId, name: trimmed),
      );
      return TripLocation(id: id, tripId: tripId, name: trimmed);
    } on SqliteException catch (error) {
      if (error.extendedResultCode == 2067) {
        throw ValidationException(
          'A location named "$trimmed" already exists on this trip.',
        );
      }
      throw DatabaseException.fromSqlite(error, table: 'locations');
    }
  }

  @override
  Future<void> deleteLocation(int locationId) async {
    final location = await _db.journeyDao.getLocationById(locationId);
    if (location == null) {
      throw const ValidationException('This location no longer exists.');
    }

    final memberJoins = await _db.memberDao.getByTrip(location.tripId);
    final referencedByMember = memberJoins.any(
      (m) => m.joinLocationId == locationId || m.leaveLocationId == locationId,
    );
    if (referencedByMember) {
      throw const ValidationException(
        'A member joins or leaves at this location. Remove that first.',
      );
    }

    final segments = (await _db.journeyDao.getSegments(location.tripId)).where(
      (s) => s.startLocationId == locationId || s.endLocationId == locationId,
    );
    if (segments.isNotEmpty) {
      throw const ValidationException(
        'This location is part of a travel segment. Remove the segment first.',
      );
    }

    await _db.journeyDao.deleteLocation(locationId);
  }

  // -- Travel segments -----------------------------------------------------------

  @override
  Stream<List<TravelSegment>> watchSegments(int tripId) => _db.journeyDao
      .watchSegments(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<TravelSegment>> getSegments(int tripId) async =>
      (await _db.journeyDao.getSegments(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<void> addSegment(
    int tripId, {
    required int startLocationId,
    required int endLocationId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final locations = (await _db.journeyDao.getLocations(
      tripId,
    )).map((row) => row.toDomain()).toList();
    final locationIds = locations.map((l) => l.id).toSet();
    if (!locationIds.contains(startLocationId) ||
        !locationIds.contains(endLocationId)) {
      throw const ValidationException(
        'Both segment endpoints must be locations of this trip.',
      );
    }
    if (startLocationId == endLocationId) {
      throw const ValidationException(
        'A segment must join two different places.',
      );
    }
    if (endTime != null && startTime != null && endTime.isBefore(startTime)) {
      throw const ValidationException(
        'The segment cannot end before it starts.',
      );
    }

    final existing = await _db.journeyDao.getSegments(tripId);
    if (existing.isNotEmpty) {
      final last = existing.reduce((a, b) => a.sequence >= b.sequence ? a : b);
      if (last.endLocationId != startLocationId) {
        throw ValidationException(
          'A new segment must continue the journey from its current end '
          '(${_nameOf(locations, last.endLocationId)}).',
        );
      }
    }

    try {
      await _db.transaction(() async {
        await _db.journeyDao.insertSegment(
          TravelSegmentsCompanion.insert(
            tripId: tripId,
            sequence: existing.length,
            startLocationId: startLocationId,
            endLocationId: endLocationId,
            startTime: Value(startTime),
            endTime: Value(endTime),
          ),
        );
        await _resyncParticipations(tripId);
      });
    } on SqliteException catch (error) {
      throw DatabaseException.fromSqlite(error, table: 'travel_segments');
    }
  }

  @override
  Future<void> updateSegment(
    int segmentId, {
    int? startLocationId,
    int? endLocationId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final segment = await _db.journeyDao.getSegmentById(segmentId);
    if (segment == null) {
      throw const ValidationException('This segment no longer exists.');
    }
    if (endTime != null && startTime != null && endTime.isBefore(startTime)) {
      throw const ValidationException(
        'The segment cannot end before it starts.',
      );
    }
    final locations = await _db.journeyDao.getLocations(segment.tripId);
    final locationIds = locations.map((location) => location.id).toSet();
    final resolvedStart = startLocationId ?? segment.startLocationId;
    final resolvedEnd = endLocationId ?? segment.endLocationId;
    if (!locationIds.contains(resolvedStart) ||
        !locationIds.contains(resolvedEnd)) {
      throw const ValidationException(
        'Both segment endpoints must be locations of this trip.',
      );
    }
    if (resolvedStart == resolvedEnd) {
      throw const ValidationException(
        'A segment must join two different places.',
      );
    }
    await _db.journeyDao.updateSegment(
      segmentId,
      TravelSegmentsCompanion(
        startLocationId: Value(resolvedStart),
        endLocationId: Value(resolvedEnd),
        startTime: Value(startTime),
        endTime: Value(endTime),
      ),
    );
    if (startLocationId != null || endLocationId != null) {
      await _resyncParticipations(segment.tripId);
    }
  }

  @override
  Future<void> deleteSegment(int segmentId) async {
    final segment = await _db.journeyDao.getSegmentById(segmentId);
    if (segment == null) {
      throw const ValidationException('This segment no longer exists.');
    }
    await _db.transaction(() async {
      await _db.journeyDao.deleteParticipationsForSegment(segmentId);
      await _db.journeyDao.deleteSegment(segmentId);
    });
    await _resyncParticipations(segment.tripId);
  }

  @override
  Future<void> resequenceSegments(List<int> orderedSegmentIds) async {
    if (orderedSegmentIds.isEmpty) {
      return;
    }
    final tripId = (await _db.journeyDao.getSegmentById(
      orderedSegmentIds.first,
    ))?.tripId;
    if (tripId == null) {
      return;
    }
    // The first segment in the new order keeps its start; every following
    // segment's start must be the previous segment's end for the route to
    // stay connected.
    for (var i = 0; i < orderedSegmentIds.length; i++) {
      final segment = await _db.journeyDao.getSegmentById(orderedSegmentIds[i]);
      if (segment == null || segment.tripId != tripId) {
        throw const ValidationException(
          'Every segment must belong to the same trip.',
        );
      }
      if (i > 0) {
        final previous = await _db.journeyDao.getSegmentById(
          orderedSegmentIds[i - 1],
        );
        if (previous!.endLocationId != segment.startLocationId) {
          throw const ValidationException(
            'Segments can only be reordered along the route, keeping each '
            'segment starting where the previous one ends.',
          );
        }
      }
    }

    final idToSequence = <int, int>{
      for (var i = 0; i < orderedSegmentIds.length; i++)
        orderedSegmentIds[i]: i,
    };
    await _db.journeyDao.resequenceSegments(idToSequence);
    await _resyncParticipations(tripId);
  }

  // -- Participation --------------------------------------------------------------

  @override
  Stream<List<MemberParticipation>> watchParticipations(int tripId) => _db
      .journeyDao
      .watchParticipations(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<MemberParticipation>> getParticipations(int tripId) async =>
      (await _db.journeyDao.getParticipations(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<void> setParticipation({
    required int memberId,
    required int segmentId,
    required bool participating,
  }) async {
    final segment = await _db.journeyDao.getSegmentById(segmentId);
    if (segment == null) {
      throw const ValidationException('This segment no longer exists.');
    }
    final member = await _db.memberDao.getById(memberId);
    if (member == null || member.tripId != segment.tripId) {
      throw const ValidationException(
        'The member must belong to the segment\'s trip.',
      );
    }
    await _db.journeyDao.upsertParticipation(
      memberId: memberId,
      segmentId: segmentId,
      participating: participating,
    );
  }

  // -- Helpers ------------------------------------------------------------------

  /// Recomputes stored participation for every member after a structural
  /// change (segment added, removed, or reordered). Explicit overrides are
  /// preserved because the calculator consults stored rows first.
  ///
  /// All writes run in a single transaction: drift coalesces the stream
  /// notification to one emission at commit, so the Journey screen rebuilds
  /// once instead of once per member per segment.
  Future<void> _resyncParticipations(int tripId) async {
    final segments = (await _db.journeyDao.getSegments(
      tripId,
    )).map((s) => s.toDomain()).toList();
    if (segments.isEmpty) {
      return;
    }
    final members = (await _db.memberDao.getByTrip(
      tripId,
    )).map((m) => m.toDomain()).toList();

    await _db.transaction(() async {
      for (final member in members) {
        final existing = (await _db.journeyDao.getParticipationsForMember(
          member.id,
        )).map((r) => r.toDomain()).toList();
        final derived = ParticipationCalculator.deriveForMember(
          member: member,
          segments: segments,
          existing: existing,
        );
        for (final entry in derived.entries) {
          await _db.journeyDao.upsertParticipation(
            memberId: member.id,
            segmentId: entry.key,
            participating: entry.value,
          );
        }
      }
    });
  }

  static String _nameOf(List<TripLocation> locations, int id) => locations
      .firstWhere(
        (l) => l.id == id,
        orElse: () => TripLocation(id: id, tripId: 0, name: '?'),
      )
      .name;
}
