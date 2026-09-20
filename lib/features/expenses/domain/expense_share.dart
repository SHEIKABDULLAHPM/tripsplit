import 'package:freezed_annotation/freezed_annotation.dart';
part 'expense_share.freezed.dart';
part 'expense_share.g.dart';

/// Immutable domain entity representing one member's share of an expense.
@freezed
sealed class ExpenseShare with _$ExpenseShare {
  const factory ExpenseShare({
    required int id,
    required int expenseId,
    required int memberId,
    @Default(0) int shareMinor,
  }) = _ExpenseShare;

  factory ExpenseShare.fromJson(Map<String, dynamic> json) =>
      _$ExpenseShareFromJson(json);
}
