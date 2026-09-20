import 'package:freezed_annotation/freezed_annotation.dart';
part 'expense_payment.freezed.dart';
part 'expense_payment.g.dart';

/// One member's cash contribution toward a single expense.
///
/// The sum of a expense's payments equals the expense's full amount. This is
/// the model that allows several people to pay for the same expense (e.g.
/// Dhar paying ₹1,200 and Gowtham ₹800 toward a shared ₹2,000 hotel bill).
@freezed
sealed class ExpensePayment with _$ExpensePayment {
  const factory ExpensePayment({
    required int id,
    required int expenseId,
    required int memberId,
    @Default(0) int amountMinor,

    /// Team this payer paid on behalf of, when team-scoped. Must be a team the
    /// payer belongs to.
    int? teamId,
  }) = _ExpensePayment;

  factory ExpensePayment.fromJson(Map<String, dynamic> json) =>
      _$ExpensePaymentFromJson(json);
}
