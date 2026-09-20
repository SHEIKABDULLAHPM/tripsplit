/// A single member's share of one expense, in minor units.
class MemberShare {
  const MemberShare({required this.memberId, required this.amountMinor});

  final int memberId;
  final int amountMinor;
}

/// Strategy for dividing an expense across participants.
///
/// The MVP ships the equal-split strategy. Future strategies (by weight,
/// custom amounts, etc.) plug in behind this interface.
abstract interface class ExpenseSplitter {
  /// Splits [totalMinor] across [memberIds], guaranteeing that the returned
  /// shares always sum exactly back to [totalMinor].
  List<MemberShare> split({
    required int totalMinor,
    required List<int> memberIds,
  });
}

/// Splits an expense equally while preserving an exact total.
///
/// Uses largest-remainder distribution: everyone receives the floor division
/// first, then the leftover paise are given one at a time to the participants
/// in order. The result is fully deterministic and always sums to
/// [totalMinor]. For example `₹100.00` split three ways yields
/// `₹33.34 / ₹33.33 / ₹33.33`.
class EqualExpenseSplitter implements ExpenseSplitter {
  const EqualExpenseSplitter();

  @override
  List<MemberShare> split({
    required int totalMinor,
    required List<int> memberIds,
  }) {
    if (totalMinor < 0) {
      throw ArgumentError.value(
        totalMinor,
        'totalMinor',
        'An expense total cannot be negative.',
      );
    }
    if (memberIds.isEmpty) {
      throw ArgumentError.value(
        memberIds,
        'memberIds',
        'At least one participant is required.',
      );
    }

    final base = totalMinor ~/ memberIds.length;
    final remainder = totalMinor % memberIds.length;

    return [
      for (var i = 0; i < memberIds.length; i++)
        MemberShare(
          memberId: memberIds[i],
          amountMinor: base + (i < remainder ? 1 : 0),
        ),
    ];
  }
}
