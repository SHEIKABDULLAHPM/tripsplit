/// A named place on a trip's journey (e.g. "Erode", "Salem").
class TripLocation {
  const TripLocation({
    required this.id,
    required this.tripId,
    required this.name,
  });

  final int id;
  final int tripId;
  final String name;
}

/// An ordered leg of a trip's journey, e.g. "Erode → Salem".
///
/// Segments exist so that expense participation can be derived from who
/// actually travelled. They are storage of intent, not navigation.
class TravelSegment {
  const TravelSegment({
    required this.id,
    required this.tripId,
    required this.sequence,
    required this.startLocationId,
    required this.endLocationId,
    this.startTime,
    this.endTime,
  });

  final int id;
  final int tripId;
  final int sequence;
  final int startLocationId;
  final int endLocationId;
  final DateTime? startTime;
  final DateTime? endTime;
}

/// Whether a member participates in a travel segment.
class MemberParticipation {
  const MemberParticipation({
    required this.memberId,
    required this.segmentId,
    required this.participating,
  });

  final int memberId;
  final int segmentId;
  final bool participating;
}

/// An organizational grouping of trip members.
class Team {
  const Team({required this.id, required this.tripId, required this.name});

  final int id;
  final int tripId;
  final String name;
}

/// Membership of a member in a team.
class TeamMember {
  const TeamMember({required this.teamId, required this.memberId});

  final int teamId;
  final int memberId;
}
