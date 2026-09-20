import 'journey.dart';

/// Persistence for the trip's journey: named locations, ordered travel
/// segments, and per-member participation in each segment.
abstract interface class JourneyRepository {
  // -- Locations ---------------------------------------------------------------

  Stream<List<TripLocation>> watchLocations(int tripId);
  Future<List<TripLocation>> getLocations(int tripId);
  Future<TripLocation> addLocation(int tripId, String name);

  /// Removes a location. Fails while any member joins or leaves there, or
  /// while it is part of a travel segment.
  Future<void> deleteLocation(int locationId);

  // -- Travel segments -----------------------------------------------------------

  Stream<List<TravelSegment>> watchSegments(int tripId);
  Future<List<TravelSegment>> getSegments(int tripId);

  /// Creates a segment from [startLocationId] to [endLocationId], appending
  /// it to the route and deriving default participation for all members.
  Future<void> addSegment(
    int tripId, {
    required int startLocationId,
    required int endLocationId,
    DateTime? startTime,
    DateTime? endTime,
  });

  Future<void> updateSegment(
    int segmentId, {
    int? startLocationId,
    int? endLocationId,
    DateTime? startTime,
    DateTime? endTime,
  });

  Future<void> deleteSegment(int segmentId);

  /// Reorders segments to the given id order (0-based); default participation
  /// is re-derived for all members afterwards.
  Future<void> resequenceSegments(List<int> orderedSegmentIds);

  // -- Participation --------------------------------------------------------------

  /// Rows where the member's participation differs from the join/leave default
  /// (explicitly toggled), plus any auto-filled rows.
  Stream<List<MemberParticipation>> watchParticipations(int tripId);
  Future<List<MemberParticipation>> getParticipations(int tripId);
  Future<void> setParticipation({
    required int memberId,
    required int segmentId,
    required bool participating,
  });
}
