import 'package:freezed_annotation/freezed_annotation.dart';
part 'settlement.freezed.dart';
part 'settlement.g.dart';

/// Progress state of a settlement transfer, derived from its obligation and
/// paid amounts. Never persisted; see [Settlement.status].
enum SettlementStatus { outstanding, partial, paid }

/// Immutable domain entity representing a settlement between two members.
///
/// A settlement is a transfer, not an expense: it never changes reported
/// spending or budget usage.
@freezed
sealed class Settlement with _$Settlement {
  const factory Settlement({
    required int id,
    required int tripId,
    required int fromMemberId,
    required int toMemberId,

    /// The obligation this settlement records, in minor units.
    @Default(0) int amountMinor,

    /// Cash actually transferred so far, in minor units. May accumulate over
    /// several payments; partial settlements are fully representable.
    @Default(0) int amountPaidMinor,
    String? note,

    /// When the obligation was recorded.
    required DateTime settledAt,

    /// When the transfer was fully paid, if it is.
    DateTime? paidAt,
    required DateTime updatedAt,
  }) = _Settlement;

  const Settlement._();

  factory Settlement.fromJson(Map<String, dynamic> json) =>
      _$SettlementFromJson(json);

  /// Derived status from recorded amounts (obligation versus paid).
  SettlementStatus get status {
    if (amountPaidMinor >= amountMinor) {
      return SettlementStatus.paid;
    }
    if (amountPaidMinor > 0) {
      return SettlementStatus.partial;
    }
    return SettlementStatus.outstanding;
  }
}
