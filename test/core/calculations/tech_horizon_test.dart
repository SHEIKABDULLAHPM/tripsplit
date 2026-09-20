import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// The mandatory Tech Horizon end-to-end scenario, exercised at the pure
/// calculation layer.
///
/// Setup (from the spec narrative):
///  - Group budget ₹2,500; contributions: Shaik ₹1,650, Suganth ₹1,050,
///    Asma ₹1,650, Man ₹350.
///  - Registration ₹730.80 (Suganth pays; shared Suganth + Man equally).
///  - Train ₹733.60 = ₹183.40 per head (all four share it), modeled with
///    two line items so that Man pays his own share: Suganth pays ₹550.20
///    and Man pays ₹183.40.
void main() {
  final now = DateTime(2026, 9, 12);
  const shaik = 1, suganth = 2, asma = 3, man = 4;

  TripLedger buildLedger() => TripLedger(
    contributions: [
      Contribution(
        id: 11,
        tripId: 1,
        memberId: shaik,
        amountMinor: 165000,
        createdAt: now,
      ),
      Contribution(
        id: 12,
        tripId: 1,
        memberId: suganth,
        amountMinor: 105000,
        createdAt: now,
      ),
      Contribution(
        id: 13,
        tripId: 1,
        memberId: asma,
        amountMinor: 165000,
        createdAt: now,
      ),
      Contribution(
        id: 14,
        tripId: 1,
        memberId: man,
        amountMinor: 35000,
        createdAt: now,
      ),
    ],
    expenses: [
      Expense(
        id: 101,
        tripId: 1,
        payerMemberId: suganth,
        description: 'Registration',
        amountMinor: 73080,
        createdAt: now,
        updatedAt: now,
      ),
      Expense(
        id: 102,
        tripId: 1,
        payerMemberId: suganth,
        description: 'Train (Suganth)',
        amountMinor: 55020,
        createdAt: now,
        updatedAt: now,
      ),
      Expense(
        id: 103,
        tripId: 1,
        payerMemberId: man,
        description: 'Train (Man)',
        amountMinor: 18340,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    shares: [
      // Registration 730.80 split between Suganth and Man.
      const ExpenseShare(
        id: 1,
        expenseId: 101,
        memberId: suganth,
        shareMinor: 36540,
      ),
      const ExpenseShare(
        id: 2,
        expenseId: 101,
        memberId: man,
        shareMinor: 36540,
      ),
      // "Train (Suganth)" 550.20 split four ways.
      const ExpenseShare(
        id: 3,
        expenseId: 102,
        memberId: shaik,
        shareMinor: 13755,
      ),
      const ExpenseShare(
        id: 4,
        expenseId: 102,
        memberId: suganth,
        shareMinor: 13755,
      ),
      const ExpenseShare(
        id: 5,
        expenseId: 102,
        memberId: asma,
        shareMinor: 13755,
      ),
      const ExpenseShare(
        id: 6,
        expenseId: 102,
        memberId: man,
        shareMinor: 13755,
      ),
      // "Train (Man)" 183.40 split four ways.
      const ExpenseShare(
        id: 7,
        expenseId: 103,
        memberId: shaik,
        shareMinor: 4585,
      ),
      const ExpenseShare(
        id: 8,
        expenseId: 103,
        memberId: suganth,
        shareMinor: 4585,
      ),
      const ExpenseShare(
        id: 9,
        expenseId: 103,
        memberId: asma,
        shareMinor: 4585,
      ),
      const ExpenseShare(
        id: 10,
        expenseId: 103,
        memberId: man,
        shareMinor: 4585,
      ),
    ],
    settlements: const [],
  );

  group('Tech Horizon scenario', () {
    test('contributions and spending totals are correct', () {
      final ledger = buildLedger();
      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: 250000,
        contributions: ledger.contributions,
        expenses: ledger.expenses,
        shares: ledger.shares,
        settlements: ledger.settlements,
      );

      expect(balances.totalContributions, 470000);
      expect(balances.totalExpenses, 146440);
      expect(balances.remainingBudget, 103560);

      final manBalance = balances.members.firstWhere((m) => m.memberId == man);
      expect(manBalance.contribution, 35000);
      expect(manBalance.actualPaid, 18340);
      expect(manBalance.expenseShare, 54880);
      expect(manBalance.netPosition, -36540);
    });

    test('cash before any settlement matches the narrative', () {
      final ledger = buildLedger();
      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: 250000,
        contributions: ledger.contributions,
        expenses: ledger.expenses,
        shares: ledger.shares,
        settlements: ledger.settlements,
      );

      final manBalance = balances.members.firstWhere((m) => m.memberId == man);
      expect(manBalance.cashRemaining, 35000 - 18340);
      expect(manBalance.cashRemaining, 16660);
    });

    test('settlement plan says Man owes Suganth the full 365.40', () {
      final ledger = buildLedger();
      final plan = SettlementCalculator.calculate(
        expenses: ledger.expenses,
        shares: ledger.shares,
        settlements: ledger.settlements,
      );

      expect(plan.suggestions, hasLength(3));
      final first = plan.suggestions.first;
      expect(first.fromMemberId, man);
      expect(first.toMemberId, suganth);
      expect(first.minor, 36540);
      expect(plan.totalOutstanding, 73220);
    });

    test('cash after the settlement lands at -198.80 for Man', () {
      final ledger = buildLedger();
      final settlementRow = Settlement(
        id: 201,
        tripId: 1,
        fromMemberId: man,
        toMemberId: suganth,
        amountMinor: 36540,
        amountPaidMinor: 36540,
        note: null,
        settledAt: DateTime(2026, 9, 13),
        paidAt: DateTime(2026, 9, 13),
        updatedAt: DateTime(2026, 9, 13),
      );

      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: 250000,
        contributions: ledger.contributions,
        expenses: ledger.expenses,
        shares: ledger.shares,
        settlements: [settlementRow],
      );

      final manBalance = balances.members.firstWhere((m) => m.memberId == man);
      expect(manBalance.cashRemaining, -19880);

      final plan = SettlementCalculator.calculate(
        expenses: ledger.expenses,
        shares: ledger.shares,
        settlements: [settlementRow],
      );
      expect(
        plan.suggestions.any((s) => s.fromMemberId == man && s.minor == 36540),
        isFalse,
      );
    });
  });
}

class TripLedger {
  const TripLedger({
    required this.contributions,
    required this.expenses,
    required this.shares,
    required this.settlements,
  });

  final List<Contribution> contributions;
  final List<Expense> expenses;
  final List<ExpenseShare> shares;
  final List<Settlement> settlements;
}
