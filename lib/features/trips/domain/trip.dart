import 'package:freezed_annotation/freezed_annotation.dart';
part 'trip.freezed.dart';
part 'trip.g.dart';

/// Immutable domain entity representing a trip.
///
/// This is the pure-Dart representation used across the domain and
/// presentation layers. Persistence mapping to the database row is handled in
/// the data layer.
@freezed
sealed class Trip with _$Trip {
  const factory Trip({
    required int id,
    required String name,
    String? description,
    @Default('INR') String currencyCode,
    DateTime? startDate,
    DateTime? endDate,

    /// Journey starting point as a simple text label (e.g. "Erode").
    String? startLocation,

    /// Planned group budget in minor units, separate from member
    /// contributions.
    @Default(0) int totalBudgetMinor,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Trip;

  factory Trip.fromJson(Map<String, dynamic> json) => _$TripFromJson(json);
}
