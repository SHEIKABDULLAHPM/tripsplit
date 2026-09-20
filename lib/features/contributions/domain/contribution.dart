import 'package:freezed_annotation/freezed_annotation.dart';
part 'contribution.freezed.dart';
part 'contribution.g.dart';

/// Immutable domain entity representing a contribution into the trip pool.
///
/// Amounts are stored in minor units (e.g. cents) for the trip currency.
@freezed
sealed class Contribution with _$Contribution {
  const factory Contribution({
    required int id,
    required int tripId,
    required int memberId,
    @Default(0) int amountMinor,
    String? note,
    required DateTime createdAt,
  }) = _Contribution;

  factory Contribution.fromJson(Map<String, dynamic> json) =>
      _$ContributionFromJson(json);
}
