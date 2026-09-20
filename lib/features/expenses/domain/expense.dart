import 'package:freezed_annotation/freezed_annotation.dart';
import 'expense_scope.dart';
part 'expense.freezed.dart';
part 'expense.g.dart';

/// Immutable domain entity representing an expense.
///
/// Expenses are source transactions; balances are derived from them at read
/// time rather than being stored.
///
/// [amountMinor] is the full amount laid out of pocket, which is the sum of
/// all [ExpensePayment] amounts. A part of it can be an
/// [externalAmountMinor]: cash paid for people/items outside the group that is
/// NOT split between the participants. The shareable group amount is
/// `amountMinor - externalAmountMinor`.
@freezed
sealed class Expense with _$Expense {
  const factory Expense({
    required int id,
    required int tripId,

    /// Primary payer of the expense (kept for display and migration
    /// compatibility; payment rows are authoritative for calculations).
    required int payerMemberId,
    required String description,

    /// What the expense applies to; drives participant defaults.
    @Default(ExpenseScope.shared) ExpenseScope scope,

    /// Travel segment this expense belongs to, when segment-based.
    int? segmentId,

    /// Team this expense applies to, when team-scoped.
    int? teamId,

    /// Every team this expense applies to, when team-scoped. The join rows
    /// behind this are authoritative; [teamId] mirrors the first entry for
    /// back-compatibility with older consumers.
    @Default(<int>[]) List<int> teamIds,
    @Default(0) int amountMinor,

    /// Cash paid by the payer that is not shared with the group.
    @Default(0) int externalAmountMinor,
    String? category,
    DateTime? spentAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Expense;

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);
}
