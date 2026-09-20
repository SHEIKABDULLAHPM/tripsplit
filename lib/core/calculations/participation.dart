import '../../features/journey/domain/journey.dart';
import '../../features/members/domain/member.dart';

/// Rules that decide who participates in a travel segment.
///
/// Participation drives the DEFAULT participants of a segment-based expense.
/// It is never an enforcement: every expense keeps an explicit participant
/// list that the user can override.
abstract final class ParticipationCalculator {
  ParticipationCalculator._();

  /// Whether [member] participated in [segment].
  ///
  /// An explicit participation row always wins. Otherwise the member's
  /// joining/leaving location is used: a member travels the sub-journey
  /// between their join and leave points. A member with no join/leave info and
  /// no explicit row is treated as participating (the historical default).
  static bool participatesInSegment({
    required int memberId,
    required TravelSegment segment,
    required int segmentOrder,
    required List<Member> members,
    required List<TravelSegment> segments,
    required List<TripLocation> locations,
    required List<MemberParticipation> participations,
  }) {
    for (final participation in participations) {
      if (participation.memberId == memberId &&
          participation.segmentId == segment.id) {
        return participation.participating;
      }
    }

    final member = _memberById(members, memberId);
    if (member == null ||
        (member.joinLocationId == null && member.leaveLocationId == null)) {
      return true;
    }

    final orders = _locationOrder(segments);
    final joinIndex = _indexOf(orders, member.joinLocationId);
    // For the leave point, find the first occurrence strictly after the join
    // index. This correctly handles journeys where the same location appears
    // multiple times (e.g. Erode→Chennai→Hyderabad→Bengaluru→Chennai→
    // Bengaluru→Erode) and a member joins/leaves at a repeated location.
    final leaveIndex = _indexOf(
      orders,
      member.leaveLocationId,
      after: joinIndex >= 0 ? joinIndex + 1 : 0,
    );

    if (member.joinLocationId != null &&
        member.leaveLocationId != null &&
        (joinIndex == -1 || leaveIndex == -1)) {
      // Join or leave point isn't on the plotted route; stay lenient.
      return true;
    }

    final startInJourney =
        member.joinLocationId == null || segmentOrder >= joinIndex;
    final endInJourney =
        member.leaveLocationId == null || (segmentOrder + 1) <= leaveIndex;
    return startInJourney && endInJourney;
  }

  /// Ids of all members who participated in [segment] (the default
  /// participants for a segment-based expense).
  static Set<int> participatingMemberIds({
    required TravelSegment segment,
    required int segmentOrder,
    required List<Member> members,
    required List<TravelSegment> segments,
    required List<TripLocation> locations,
    required List<MemberParticipation> participations,
  }) {
    final result = <int>{};
    for (final member in members) {
      if (participatesInSegment(
        memberId: member.id,
        segment: segment,
        segmentOrder: segmentOrder,
        members: members,
        segments: segments,
        locations: locations,
        participations: participations,
      )) {
        result.add(member.id);
      }
    }
    return result;
  }

  /// Derives the full per-segment participation map for one member from their
  /// join/leave location, used when (re)syncing stored participation.
  static Map<int, bool> deriveForMember({
    required Member member,
    required List<TravelSegment> segments,
    required List<MemberParticipation> existing,
  }) {
    final result = <int, bool>{};
    if (segments.isEmpty) {
      return result;
    }
    final lifted = Member(
      id: member.id,
      tripId: member.tripId,
      name: member.name,
      joinLocationId: member.joinLocationId,
      leaveLocationId: member.leaveLocationId,
      createdAt: member.createdAt,
    );
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      result[segment.id] = participatesInSegment(
        memberId: member.id,
        segment: segment,
        segmentOrder: i,
        members: [lifted],
        segments: segments,
        locations: const <TripLocation>[],
        participations: existing,
      );
    }
    return result;
  }

  static Member? _memberById(List<Member> members, int memberId) {
    for (final member in members) {
      if (member.id == memberId) {
        return member;
      }
    }
    return null;
  }

  /// Ordered location ids along the route: [seg0.start, seg0.end, seg1.end, ...].
  static List<int> _locationOrder(List<TravelSegment> segments) {
    final ordered = <int>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (i == 0) {
        ordered.add(segment.startLocationId);
      }
      ordered.add(segment.endLocationId);
    }
    return ordered;
  }

  /// Returns the index of the first occurrence of [id] in [items], starting
  /// the search at position [after]. Returns -1 when [id] is null or not
  /// found at or after [after].
  static int _indexOf(List<int> items, int? id, {int after = 0}) {
    if (id == null) {
      return -1;
    }
    for (var i = after; i < items.length; i++) {
      if (items[i] == id) return i;
    }
    return -1;
  }
}
