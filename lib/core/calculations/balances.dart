import 'dart:math' as math;

import '../../features/contributions/domain/contribution.dart';
import '../../features/expenses/domain/expense.dart';
import '../../features/expenses/domain/expense_payment.dart';
import '../../features/expenses/domain/expense_share.dart';
import '../../features/settlements/domain/settlement.dart';

/// Per-member financial breakdown shown on the Balances screen.
///
/// The five figures deliberately stay distinct so that users can see exactly
/// what each number represents:
///  - [contribution]: cash brought into the trip pool;
///  - [actualPaid]: total expense money this member actually laid out of
///    pocket (including any external, non-group portion);
///  - [expenseShare]: total expense responsibility assigned to this member;
///  - [netPosition]: group outlay (amount paid minus the external portion)
///    minus [expenseShare] — who owes whom, ignoring cash outside the group;
///  - [cashRemaining]: contributions plus settlements received (paid amounts)
///    minus actual payments minus settlements paid out.
///  - [effectiveNetPosition]: [netPosition] adjusted for settlements — the
///    true outstanding amount after accounting for cash transfers.
class MemberBalance {
  const MemberBalance({
    required this.memberId,
    required this.contribution,
    required this.actualPaid,
    required this.expenseShare,
    required this.netPosition,
    required this.cashRemaining,
    required this.effectiveNetPosition,
  });

  final int memberId;
  final int contribution;
  final int actualPaid;
  final int expenseShare;
  final int netPosition;
  final int cashRemaining;

  /// [netPosition] adjusted for settlements — reflects the true outstanding
  /// amount after cash transfers between members.
  final int effectiveNetPosition;

  /// How much this member must still pay out to the group.
  int get amountToPay => math.max(0, -effectiveNetPosition);

  /// How much this member is owed by the group.
  int get amountToReceive => math.max(0, effectiveNetPosition);

  /// Short, user-facing label for the effective net position.
  String get netLabel => effectiveNetPosition > 0
      ? 'Receives'
      : effectiveNetPosition < 0
      ? 'Owes'
      : 'Balanced';
}

/// Aggregate balances for a single trip.
class BalanceResult {
  const BalanceResult({
    required this.totalContributions,
    required this.totalExpenses,
    required this.remainingBudget,
    required this.outstandingMinor,
    required this.members,
  });

  final int totalContributions;

  /// Sum of all group-shareable expense amounts (full amounts minus the
  /// external, non-group portions). This is the money spent from the group
  /// budget.
  final int totalExpenses;

  /// Group budget minus [totalExpenses].
  final int remainingBudget;

  final List<MemberBalance> members;

  /// Total still owed across the group after recorded settlements are applied.
  /// Derived from the settlement plan, not raw net positions.
  final int outstandingMinor;

  /// Money actually spent from the group budget (equals [totalExpenses]).
  int get paidMinor => totalExpenses;

  /// Group budget minus recorded expenses.
  int get remainingBudgetMinor => remainingBudget;

  /// Cash remaining in the pool after payments and settled transfers.
  int get totalCashRemaining =>
      members.fold(0, (sum, m) => sum + m.cashRemaining);
}

/// How one expense affected a single member's group position.
class MemberExpenseEffect {
  const MemberExpenseEffect({
    required this.expenseId,
    required this.memberId,
    required this.paidMinor,
    required this.shareMinor,
  });

  final int expenseId;
  final int memberId;

  /// Group-shareable amount this member paid for the expense (external
  /// portion attributed to the primary payer).
  final int paidMinor;

  /// The member's explicit share of the expense.
  final int shareMinor;

  /// Net effect: positive = this member is owed money by the group for this
  /// expense; negative = they owe.
  int get netMinor => paidMinor - shareMinor;
}

/// Payment helpers shared by the balance and settlement engines.
///
/// The expense's [ExpensePayments] rows are authoritative when present (the
/// multi-payer model); otherwise the legacy single payer pays the full amount.
abstract final class PaymentAllocator {
  PaymentAllocator._();

  /// Payment rows grouped by expense id.
  static Map<int, List<ExpensePayment>> byExpense(
    List<ExpensePayment> payments,
  ) {
    final grouped = <int, List<ExpensePayment>>{};
    for (final payment in payments) {
      grouped.putIfAbsent(payment.expenseId, () => []).add(payment);
    }
    return grouped;
  }

  /// Full out-of-pocket amount each member paid for [expense].
  static List<ExpensePayment> fullPayments(
    Expense expense,
    List<ExpensePayment> rows,
  ) {
    if (rows.isNotEmpty) {
      return rows;
    }
    return [
      ExpensePayment(
        id: -expense.id,
        expenseId: expense.id,
        memberId: expense.payerMemberId,
        amountMinor: expense.amountMinor,
      ),
    ];
  }

  /// Group-shareable amount each member paid for [expense], in minor units.
  ///
  /// The external, non-group portion is attributed to the primary payer so
  /// that `sum(group outlay) == amount - external == sum(shares)` and the
  /// aggregate net positions always sum to zero.
  static Map<int, int> groupOutlayByMember(
    Expense expense,
    List<ExpensePayment> rows,
  ) {
    final result = <int, int>{};
    final payments = fullPayments(expense, rows);
    for (final payment in payments) {
      var credit = payment.amountMinor;
      if (payment.memberId == expense.payerMemberId) {
        credit -= expense.externalAmountMinor;
      }
      result[payment.memberId] = (result[payment.memberId] ?? 0) + credit;
    }
    return result;
  }

  /// Per-expense effects for every member of the trip.
  static List<MemberExpenseEffect> effectsPerExpense({
    required Expense expense,
    required List<ExpenseShare> shares,
    required Map<int, List<ExpensePayment>> paymentsByExpense,
  }) {
    final outlay = groupOutlayByMember(
      expense,
      paymentsByExpense[expense.id] ?? const [],
    );
    final shareByMember = <int, int>{};
    for (final share in shares) {
      shareByMember[share.memberId] = share.shareMinor;
    }
    final memberIds = <int>{...outlay.keys, ...shareByMember.keys};
    return [
      for (final memberId in memberIds.toList()..sort())
        MemberExpenseEffect(
          expenseId: expense.id,
          memberId: memberId,
          paidMinor: outlay[memberId] ?? 0,
          shareMinor: shareByMember[memberId] ?? 0,
        ),
    ];
  }
}

/// Derives per-member balances from source transactions.
///
/// Balances are always computed at read time; nothing derived is persisted as
/// an authoritative database column.
abstract final class BalanceCalculator {
  BalanceCalculator._();

  static BalanceResult calculate({
    required int tripBudgetMinor,
    required List<Contribution> contributions,
    required List<Expense> expenses,
    required List<ExpenseShare> shares,
    required List<Settlement> settlements,
    List<ExpensePayment> payments = const [],
    int postSettlementOutstanding = -1,
  }) {
    // A negative sentinel means "not provided — compute from raw nets".
    final hasSettlementResult = postSettlementOutstanding >= 0;
    final contributionByMember = <int, int>{};
    for (final contribution in contributions) {
      contributionByMember[contribution.memberId] =
          (contributionByMember[contribution.memberId] ?? 0) +
          contribution.amountMinor;
    }

    final paymentsByExpense = PaymentAllocator.byExpense(payments);
    final paidByMember = <int, int>{};
    final groupOutlayByMember = <int, int>{};
    var totalExpenses = 0;
    for (final expense in expenses) {
      _validateExternal(expense);
      final groupPortion = expense.amountMinor - expense.externalAmountMinor;
      totalExpenses += groupPortion;

      final rows = paymentsByExpense[expense.id] ?? const [];
      final full = PaymentAllocator.fullPayments(expense, rows);
      for (final payment in full) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
      final outlay = PaymentAllocator.groupOutlayByMember(expense, rows);
      for (final entry in outlay.entries) {
        groupOutlayByMember[entry.key] =
            (groupOutlayByMember[entry.key] ?? 0) + entry.value;
      }
    }

    final shareByMember = <int, int>{};
    for (final share in shares) {
      if (share.shareMinor < 0) {
        throw ArgumentError.value(
          share,
          'shares',
          'Share amounts cannot be negative.',
        );
      }
      shareByMember[share.memberId] =
          (shareByMember[share.memberId] ?? 0) + share.shareMinor;
    }

    final receivedByMember = <int, int>{};
    final paidOutByMember = <int, int>{};
    for (final settlement in settlements) {
      final paid = settlement.amountPaidMinor;
      if (paid <= 0) {
        continue;
      }
      receivedByMember[settlement.toMemberId] =
          (receivedByMember[settlement.toMemberId] ?? 0) + paid;
      paidOutByMember[settlement.fromMemberId] =
          (paidOutByMember[settlement.fromMemberId] ?? 0) + paid;
    }

    final memberIds = <int>{}
      ..addAll(contributionByMember.keys)
      ..addAll(paidByMember.keys)
      ..addAll(shareByMember.keys)
      ..addAll(receivedByMember.keys)
      ..addAll(paidOutByMember.keys);

    var totalContributions = 0;
    for (final contribution in contributions) {
      totalContributions += contribution.amountMinor;
    }

    final int outstanding;
    if (hasSettlementResult) {
      outstanding = postSettlementOutstanding;
    } else {
      // Compute per-member net and sum the debts (members who owe money).
      var debtSum = 0;
      for (final id in memberIds) {
        final net = (groupOutlayByMember[id] ?? 0) - (shareByMember[id] ?? 0);
        if (net < 0) debtSum += -net;
      }
      outstanding = debtSum;
    }

    return BalanceResult(
      totalContributions: totalContributions,
      totalExpenses: totalExpenses,
      remainingBudget: tripBudgetMinor - totalExpenses,
      outstandingMinor: outstanding,
      members: [
        for (final id in memberIds.toList()..sort())
          MemberBalance(
            memberId: id,
            contribution: contributionByMember[id] ?? 0,
            actualPaid: paidByMember[id] ?? 0,
            expenseShare: shareByMember[id] ?? 0,
            netPosition:
                (groupOutlayByMember[id] ?? 0) - (shareByMember[id] ?? 0),
            cashRemaining:
                (contributionByMember[id] ?? 0) +
                (receivedByMember[id] ?? 0) -
                (paidByMember[id] ?? 0) -
                (paidOutByMember[id] ?? 0),
            effectiveNetPosition:
                (groupOutlayByMember[id] ?? 0) - (shareByMember[id] ?? 0) +
                (receivedByMember[id] ?? 0) -
                (paidOutByMember[id] ?? 0),
          ),
      ],
    );
  }

  static void _validateExternal(Expense expense) {
    if (expense.amountMinor < 0) {
      throw ArgumentError.value(
        expense,
        'expenses',
        'Expense amounts cannot be negative.',
      );
    }
    if (expense.externalAmountMinor < 0 ||
        expense.externalAmountMinor >= expense.amountMinor) {
      throw ArgumentError.value(
        expense,
        'expenses',
        'The external portion must be smaller than the expense amount so '
            'some of the expense is shared.',
      );
    }
  }
}
