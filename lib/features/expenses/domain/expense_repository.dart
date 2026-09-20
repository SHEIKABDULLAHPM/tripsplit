import 'expense.dart';
import 'expense_payment.dart';
import 'expense_scope.dart';
import 'expense_share.dart';

/// Abstract contract for persisting [Expense], [ExpenseShare] and
/// [ExpensePayment] entities.
///
/// Implementations live in the data layer; the domain and presentation layers
/// depend only on this interface. Expenses are written together with their
/// shares and payments inside a transaction so the share-total and payment-sum
/// invariants are never broken.
abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchByTrip(int tripId);
  Stream<Expense?> watchById(int id);
  Future<List<Expense>> getByTrip(int tripId);
  Future<Expense?> getById(int id);

  /// Creates an expense and its equal-split shares + payment rows in one
  /// transaction.
  ///
  /// [amountMinor] is the full payment made across all payers.
  /// [externalAmountMinor] (default zero) is the portion that is never shared
  /// with the group; the remaining `amountMinor - externalAmountMinor` is split
  /// equally between the participants.
  ///
  /// When [otherPayers] is empty the primary [payerMemberId] pays the full
  /// amount. Otherwise the primary pays `amountMinor` minus the sum of
  /// [otherPayers]; every payer besides the primary must still be a participant
  /// of the expense (they pay for part of the expense they share).
  ///
  /// [teamIds] lists every team this expense applies to (written into a join
  /// table); at least one team is required for [ExpenseScope.team]. When empty
  /// and [teamId] is provided the legacy single-team path is used, with
  /// `teamIds == [teamId]` implied. Each team payer may record the [teamId] they
  /// paid on behalf of on the payment object; the [payerTeamId] does the same
  /// for the primary payer. A payer attributed to a team must be a member of
  /// that team.
  /// [customShares] maps memberId → shareMinor and is only used when
  /// [scope] is [ExpenseScope.custom]. The shares must sum exactly to
  /// `amountMinor - externalAmountMinor`.
  Future<void> createExpense({
    required int tripId,
    required String description,
    required int amountMinor,
    int externalAmountMinor = 0,
    required int payerMemberId,
    ExpenseScope scope = ExpenseScope.shared,
    int? segmentId,
    int? teamId,
    List<int> teamIds = const [],
    int? payerTeamId,
    String? category,
    DateTime? spentAt,
    List<int> participantMemberIds = const [],
    List<ExpensePayment> otherPayers = const [],
    Map<int, int> customShares = const {},
  });

  /// Replaces an expense, its shares and its payments in one transaction.
  ///
  /// [teamIds] lists every team this expense applies to; see [createExpense]
  /// for the resolution and validation rules. [customShares] maps
  /// memberId → shareMinor and is only used when [scope] is
  /// [ExpenseScope.custom]. The shares must sum exactly to
  /// `amountMinor - externalAmountMinor`.
  Future<void> updateExpense({
    required int expenseId,
    required String description,
    required int amountMinor,
    int externalAmountMinor = 0,
    required int payerMemberId,
    ExpenseScope scope = ExpenseScope.shared,
    int? segmentId,
    int? teamId,
    List<int> teamIds = const [],
    int? payerTeamId,
    String? category,
    DateTime? spentAt,
    List<int> participantMemberIds = const [],
    List<ExpensePayment> otherPayers = const [],
    Map<int, int> customShares = const {},
  });

  /// Deletes an expense together with its shares and payments without breaking
  /// the share-total invariant.
  Future<void> deleteExpense({required int tripId, required int expenseId});

  Future<List<ExpenseShare>> getSharesFor(int expenseId);
  Future<List<ExpensePayment>> getPaymentsFor(int expenseId);
}
