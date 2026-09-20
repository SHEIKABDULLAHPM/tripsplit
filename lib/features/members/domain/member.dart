import 'package:freezed_annotation/freezed_annotation.dart';
part 'member.freezed.dart';
part 'member.g.dart';

/// Immutable domain entity representing a member of a trip.
@freezed
sealed class Member with _$Member {
  const factory Member({
    required int id,
    required int tripId,
    required String name,

    /// Location where this member joined the journey (nullable = from the
    /// start). Used to derive default segment participation.
    int? joinLocationId,

    /// Location where this member left the journey (nullable = until the end).
    int? leaveLocationId,
    required DateTime createdAt,
  }) = _Member;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
}
