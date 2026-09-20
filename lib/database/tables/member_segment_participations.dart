import 'package:drift/drift.dart';

import 'members.dart';
import 'travel_segments.dart';

/// Whether a member participates in a specific travel segment.
///
/// Participation is the single source of truth for segment-based expense
/// defaults. A member with no row for a segment is treated as participating by
/// default; explicit rows allow joining/leaving and per-segment overrides.
@DataClassName('MemberSegmentParticipationRow')
@TableIndex(name: 'idx_participations_member', columns: {#memberId})
@TableIndex(name: 'idx_participations_segment', columns: {#segmentId})
class MemberSegmentParticipations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();
  IntColumn get segmentId =>
      integer().references(TravelSegments, #id, onDelete: KeyAction.cascade)();
  BoolColumn get participating => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {memberId, segmentId},
  ];
}
