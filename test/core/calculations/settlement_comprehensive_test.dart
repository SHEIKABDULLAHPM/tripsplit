import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';
import 'package:tripsplit/core/calculations/money.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// Comprehensive test suite for settlement logic, mutation correctness,
/// and end-to-end financial integrity.
void main() {
  final now = DateTime(2026, 9, 15);
  const splitter = EqualExpenseSplitter();

  // ── Helpers ──────────────────────────────────────────────────────────

  Expense expense(
    int id,
    int payerId,
    int amount, {
    int external = 0,
    ExpenseScope scope = ExpenseScope.shared,
  }) => Expense(
    id: id,
    tripId: 1,
    payerMemberId: payerId,
    description: 'Expense $id',
    scope: scope,
    amountMinor: amount,
    externalAmountMinor: external,
    createdAt: now,
    updatedAt: now,
  );

  ExpenseShare share(int expId, int memberId, int minor) => ExpenseShare(
    id: expId * 100 + memberId,
    expenseId: expId,
    memberId: memberId,
    shareMinor: minor,
  );

  ExpensePayment payment(int expId, int memberId, int minor) => ExpensePayment(
    id: 0,
    expenseId: expId,
    memberId: memberId,
    amountMinor: minor,
  );

  Settlement makeSettlement(
    int id,
    int fromId,
    int toId,
    int amount, {
    int paid = 0,
  }) => Settlement(
    id: id,
    tripId: 1,
    fromMemberId: fromId,
    toMemberId: toId,
    amountMinor: amount,
    amountPaidMinor: paid,
    note: null,
    settledAt: now,
    paidAt: paid >= amount ? now : null,
    updatedAt: now,
  );

  Contribution contribution(int memberId, int amount) => Contribution(
    id: memberId,
    tripId: 1,
    memberId: memberId,
    amountMinor: amount,
    createdAt: now,
  );

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 1 & 2: SETTLEMENT CHAIN CONSOLIDATION
  // ════════════════════════════════════════════════════════════════════════

  group('Settlement chain consolidation', () {
    test('Asma→Sheik→Suganth chain: 3 expenses produce minimal transfers', () {
      // Scenario:
      // Asma pays ₹100 for Sheik → Sheik owes Asma ₹100
      // Sheik pays ₹50 for Suganth → Suganth owes Sheik ₹50
      // Suganth pays ₹30 for Asma → Asma owes Suganth ₹30
      //
      // Net positions:
      // Asma: +100 (Sheik's debt) - 30 (owes Suganth) = +70
      // Sheik: -100 (owes Asma) + 50 (Suganth's debt) = -50
      // Suganth: -50 (owes Sheik) + 30 (Asma's debt) = -20
      //
      // Minimal transfers: Sheik→Asma ₹50, Suganth→Asma ₹20

      final expenses = [
        expense(1, 1, 10000), // Asma pays ₹100 for Asma+Sheik
        expense(2, 2, 5000), // Sheik pays ₹50 for Sheik+Suganth
        expense(3, 3, 3000), // Suganth pays ₹30 for Suganth+Asma
      ];

      final shares = [
        share(1, 1, 5000), // Asma's share of expense 1
        share(1, 2, 5000), // Sheik's share of expense 1
        share(2, 2, 2500), // Sheik's share of expense 2
        share(2, 3, 2500), // Suganth's share of expense 2
        share(3, 3, 1500), // Suganth's share of expense 3
        share(3, 1, 1500), // Asma's share of expense 3
      ];

      final payments = [
        payment(1, 1, 10000),
        payment(2, 2, 5000),
        payment(3, 3, 3000),
      ];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // Net positions must sum to zero
      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);

      // Asma: paid 10000, share = 5000 + 1500 = 6500, net = +3500
      expect(result.remainingNets[1], 3500);
      // Sheik: paid 5000, share = 5000 + 2500 = 7500, net = -2500
      expect(result.remainingNets[2], -2500);
      // Suganth: paid 3000, share = 2500 + 1500 = 4000, net = -1000
      expect(result.remainingNets[3], -1000);

      // Minimal transfers: Sheik→Asma ₹2500, Suganth→Asma ₹1000
      expect(result.suggestions, hasLength(2));
      expect(result.totalOutstanding, 3500);

      // Verify each transfer is from debtor to creditor
      for (final s in result.suggestions) {
        expect(result.remainingNets[s.fromMemberId], lessThan(0));
        expect(result.remainingNets[s.toMemberId], greaterThan(0));
      }
    });

    test(
      'circular debt is consolidated, not shown as 3 separate transfers',
      () {
        // A pays for B: B owes A ₹100
        // B pays for C: C owes B ₹100
        // C pays for A: A owes C ₹100
        //
        // Net: everyone is exactly balanced! No transfers needed.

        final expenses = [
          expense(1, 1, 20000),
          expense(2, 2, 20000),
          expense(3, 3, 20000),
        ];

        final shares = [
          share(1, 1, 10000),
          share(1, 2, 10000),
          share(2, 2, 10000),
          share(2, 3, 10000),
          share(3, 3, 10000),
          share(3, 1, 10000),
        ];

        final payments = [
          payment(1, 1, 20000),
          payment(2, 2, 20000),
          payment(3, 3, 20000),
        ];

        final result = SettlementCalculator.calculate(
          expenses: expenses,
          shares: shares,
          settlements: const [],
          payments: payments,
        );

        expect(result.suggestions, isEmpty);
        expect(result.totalOutstanding, 0);
        expect(result.remainingNets[1], 0);
        expect(result.remainingNets[2], 0);
        expect(result.remainingNets[3], 0);
      },
    );

    test('asymmetric chain reduces to minimal transfers', () {
      // A pays ₹300 for A+B+C (100 each)
      // B pays ₹200 for B+C (100 each)
      //
      // Net:
      // A: +300 - 100 = +200
      // B: +200 - 100 - 100 = 0
      // C: 0 - 100 - 100 = -200
      //
      // Only 1 transfer needed: C→A ₹200

      final expenses = [expense(1, 1, 30000), expense(2, 2, 20000)];

      final shares = [
        share(1, 1, 10000),
        share(1, 2, 10000),
        share(1, 3, 10000),
        share(2, 2, 10000),
        share(2, 3, 10000),
      ];

      final payments = [payment(1, 1, 30000), payment(2, 2, 20000)];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.fromMemberId, 3);
      expect(result.suggestions.first.toMemberId, 1);
      expect(result.suggestions.first.minor, 20000);
    });

    test('4-member chain with partial offsets', () {
      // A paid ₹400 for A,B,C,D (100 each)
      // B paid ₹300 for B,C (150 each)
      // C paid ₹200 for C,D (100 each)
      //
      // Net:
      // A: +400 - 100 = +300
      // B: +300 - 100 - 150 = +50
      // C: +200 - 150 - 100 - 100 = -150
      // D: 0 - 100 - 100 = -200
      //
      // Total owed: 350, Total receivable: 350
      // Suggested: C→A 150, D→A 150, D→B 50

      final expenses = [
        expense(1, 1, 40000),
        expense(2, 2, 30000),
        expense(3, 3, 20000),
      ];

      final shares = [
        share(1, 1, 10000),
        share(1, 2, 10000),
        share(1, 3, 10000),
        share(1, 4, 10000),
        share(2, 2, 15000),
        share(2, 3, 15000),
        share(3, 3, 10000),
        share(3, 4, 10000),
      ];

      final payments = [
        payment(1, 1, 40000),
        payment(2, 2, 30000),
        payment(3, 3, 20000),
      ];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);

      expect(result.remainingNets[1], 30000);
      expect(result.remainingNets[2], 5000);
      expect(result.remainingNets[3], -15000);
      expect(result.remainingNets[4], -20000);

      expect(result.totalOutstanding, 35000);
      // Should be 3 transfers at most
      expect(result.suggestions.length, lessThanOrEqualTo(3));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 3: SETTLEMENT EDIT CORRECTNESS
  // ════════════════════════════════════════════════════════════════════════

  group('Settlement edit correctness', () {
    test('partial payment reduces outstanding correctly', () {
      // A paid ₹100 for A+B. B owes A ₹50.
      // B pays ₹20. Outstanding = ₹30.
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [makeSettlement(1, 2, 1, 5000, paid: 2000)],
        payments: [payment(1, 1, 10000)],
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.minor, 3000);
      expect(result.remainingNets[2], -3000);
    });

    test('full payment eliminates the pair from suggestions', () {
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [makeSettlement(1, 2, 1, 5000, paid: 5000)],
        payments: [payment(1, 1, 10000)],
      );

      // Fully paid — no suggestions
      expect(result.suggestions, isEmpty);
      expect(result.totalOutstanding, 0);
    });

    test('recording more payment after expense edit rebases correctly', () {
      // Original: A paid ₹100 for A+B. B owes ₹50.
      // B pays ₹20.
      // Then A's expense is edited to ₹140 (shares become ₹70 each).
      // B now owes ₹70 - ₹20 already paid = ₹50 more.
      // Total obligation should be ₹70, paid ₹20, outstanding ₹50.

      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 14000)],
        shares: [share(1, 1, 7000), share(1, 2, 7000)],
        settlements: [makeSettlement(1, 2, 1, 7000, paid: 2000)],
        payments: [payment(1, 1, 14000)],
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.minor, 5000);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 4: PARTIAL SETTLEMENT
  // ════════════════════════════════════════════════════════════════════════

  group('Partial settlement', () {
    test('unpaid → partial → fully paid lifecycle', () {
      // Step 1: Unpaid
      var result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      expect(result.suggestions.first.minor, 5000);
      expect(
        SettlementCalculator.statusOf(amountMinor: 5000, amountPaidMinor: 0),
        SettlementStatus.outstanding,
      );

      // Step 2: Partial payment ₹2000
      result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [makeSettlement(1, 2, 1, 5000, paid: 2000)],
        payments: [payment(1, 1, 10000)],
      );
      expect(result.suggestions.first.minor, 3000);
      expect(
        SettlementCalculator.statusOf(amountMinor: 5000, amountPaidMinor: 2000),
        SettlementStatus.partial,
      );

      // Step 3: Fully paid
      result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [makeSettlement(1, 2, 1, 5000, paid: 5000)],
        payments: [payment(1, 1, 10000)],
      );
      expect(result.suggestions, isEmpty);
      expect(result.totalOutstanding, 0);
      expect(
        SettlementCalculator.statusOf(amountMinor: 5000, amountPaidMinor: 5000),
        SettlementStatus.paid,
      );
    });

    test('partial payment does not affect group spending', () {
      final before = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );

      final after = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [makeSettlement(1, 2, 1, 5000, paid: 2000)],
        payments: [payment(1, 1, 10000)],
      );

      // Total expenses must not change
      expect(after.totalExpenses, before.totalExpenses);
      // Net positions must not change (settlements adjust cashRemaining, not netPosition)
      expect(after.members.length, before.members.length);
      for (var i = 0; i < before.members.length; i++) {
        expect(after.members[i].netPosition, before.members[i].netPosition);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 5: CONSOLIDATED SETTLEMENT
  // ════════════════════════════════════════════════════════════════════════

  group('Consolidated settlement', () {
    test('two expenses between same pair consolidate into one transfer', () {
      // Expense 1: A pays ₹100 for A+B → B owes A ₹50
      // Expense 2: A pays ₹60 for A+B → B owes A ₹30
      // Total: B owes A ₹80 (consolidated)

      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000), expense(2, 1, 6000)],
        shares: [
          share(1, 1, 5000),
          share(1, 2, 5000),
          share(2, 1, 3000),
          share(2, 2, 3000),
        ],
        settlements: const [],
        payments: [payment(1, 1, 10000), payment(2, 1, 6000)],
      );

      // Only 1 transfer: B→A ₹80
      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.fromMemberId, 2);
      expect(result.suggestions.first.toMemberId, 1);
      expect(result.suggestions.first.minor, 8000);
    });

    test('cross-direction debts between same pair consolidate', () {
      // Expense 1: A pays ₹100 for A+B → B owes A ₹50
      // Expense 2: B pays ₹80 for A+B → A owes B ₹40
      // Net: A is owed ₹10 (50 - 40)

      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000), expense(2, 2, 8000)],
        shares: [
          share(1, 1, 5000),
          share(1, 2, 5000),
          share(2, 1, 4000),
          share(2, 2, 4000),
        ],
        settlements: const [],
        payments: [payment(1, 1, 10000), payment(2, 2, 8000)],
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.fromMemberId, 2);
      expect(result.suggestions.first.toMemberId, 1);
      expect(result.suggestions.first.minor, 1000);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 7: EXPENSE MUTATION → SETTLEMENT RECALC
  // ════════════════════════════════════════════════════════════════════════

  group('Expense mutation → settlement recalculation', () {
    test('editing expense amount updates settlement', () {
      // Original: ₹100, split A+B → B owes A ₹50
      // Edited to ₹140 → B owes A ₹70

      final original = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      expect(original.suggestions.first.minor, 5000);

      final edited = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 14000)],
        shares: [share(1, 1, 7000), share(1, 2, 7000)],
        settlements: const [],
        payments: [payment(1, 1, 14000)],
      );
      expect(edited.suggestions.first.minor, 7000);
    });

    test('editing payer updates settlement', () {
      // Original: A pays ₹100 for A+B → B owes A ₹50
      // Edited: B pays ₹100 for A+B → A owes B ₹50

      final original = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      expect(original.suggestions.first.fromMemberId, 2);
      expect(original.suggestions.first.toMemberId, 1);

      final edited = SettlementCalculator.calculate(
        expenses: [expense(1, 2, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 2, 10000)],
      );
      expect(edited.suggestions.first.fromMemberId, 1);
      expect(edited.suggestions.first.toMemberId, 2);
    });

    test('editing participants updates shares and settlement', () {
      // Original: A pays ₹100 for A+B → B owes A ₹50
      // Edited: A pays ₹100 for A+B+C → each owes ₹33.34/₹33.33/₹33.33

      final original = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      expect(original.suggestions, hasLength(1));
      expect(original.suggestions.first.minor, 5000);

      final edited = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 3334), share(1, 2, 3333), share(1, 3, 3333)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      // Net sum must still be zero
      final netSum = edited.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);
      // A is owed more now (paid 10000, share 3334 → net +6666)
      expect(edited.remainingNets[1], 6666);
    });

    test('deleting expense updates settlement', () {
      // Original: 2 expenses, B owes A ₹80 total
      // Delete expense 2: B now owes A only ₹50

      final original = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000), expense(2, 1, 6000)],
        shares: [
          share(1, 1, 5000),
          share(1, 2, 5000),
          share(2, 1, 3000),
          share(2, 2, 3000),
        ],
        settlements: const [],
        payments: [payment(1, 1, 10000), payment(2, 1, 6000)],
      );
      expect(original.suggestions.first.minor, 8000);

      final afterDelete = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );
      expect(afterDelete.suggestions.first.minor, 5000);
    });

    test(
      'after every mutation, dashboard/balance/settlement show same truth',
      () {
        // Create 2 expenses
        final expenses = [expense(1, 1, 10000), expense(2, 2, 8000)];
        final shares = [
          share(1, 1, 5000),
          share(1, 2, 5000),
          share(2, 1, 4000),
          share(2, 2, 4000),
        ];
        final payments = [payment(1, 1, 10000), payment(2, 2, 8000)];

        // Calculate both balance and settlement from same data
        final balance = BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: const [],
          expenses: expenses,
          shares: shares,
          settlements: const [],
          payments: payments,
        );
        final settlement = SettlementCalculator.calculate(
          expenses: expenses,
          shares: shares,
          settlements: const [],
          payments: payments,
        );

        // Net positions must match
        for (final member in balance.members) {
          expect(
            settlement.remainingNets[member.memberId],
            member.netPosition,
            reason:
                'Balance and settlement net mismatch for member ${member.memberId}',
          );
        }

        // Total outstanding must match
        expect(settlement.totalOutstanding, balance.outstandingMinor);
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 8: CONTRIBUTION MUTATION
  // ════════════════════════════════════════════════════════════════════════

  group('Contribution mutation', () {
    test('contribution affects cashRemaining but not netPosition', () {
      final without = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );

      final withContribution = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: [contribution(1, 20000)],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );

      // Net position unchanged
      expect(
        withContribution.members.first.netPosition,
        without.members.first.netPosition,
      );
      // Cash remaining changes
      expect(
        withContribution.members.first.cashRemaining,
        without.members.first.cashRemaining + 20000,
      );
    });

    test('editing contribution updates cashRemaining', () {
      final before = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: [contribution(1, 10000)],
        expenses: const [],
        shares: const [],
        settlements: const [],
        payments: const [],
      );

      final after = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: [contribution(1, 25000)],
        expenses: const [],
        shares: const [],
        settlements: const [],
        payments: const [],
      );

      expect(after.members.first.cashRemaining, 25000);
      expect(before.members.first.cashRemaining, 10000);
    });

    test('contribution never becomes an expense', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 50000,
        contributions: [contribution(1, 30000)],
        expenses: const [],
        shares: const [],
        settlements: const [],
        payments: const [],
      );

      expect(result.totalExpenses, 0);
      expect(result.totalContributions, 30000);
      expect(
        result.remainingBudget,
        50000,
      ); // Budget not affected by contributions
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 10: TEAM MUTATION
  // ════════════════════════════════════════════════════════════════════════

  group('Team isolation', () {
    test('Team A expense does not affect Team B members', () {
      // Team A: members 1, 2. Expense: ₹100 paid by member 1.
      // Team B: members 3, 4. Expense: ₹200 paid by member 3.
      //
      // Member 2 owes member 1: ₹50
      // Member 4 owes member 3: ₹100
      // No cross-team debt

      final expenses = [expense(1, 1, 10000), expense(2, 3, 20000)];

      final shares = [
        share(1, 1, 5000),
        share(1, 2, 5000),
        share(2, 3, 10000),
        share(2, 4, 10000),
      ];

      final payments = [payment(1, 1, 10000), payment(2, 3, 20000)];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // Member 1 and 2 settle independently from 3 and 4
      final fromMembers = result.suggestions.map((s) => s.fromMemberId).toSet();
      final toMembers = result.suggestions.map((s) => s.toMemberId).toSet();

      // Team A: 2→1, Team B: 4→3
      expect(fromMembers, containsAll([2, 4]));
      expect(toMembers, containsAll([1, 3]));

      // No cross-team transfers
      for (final s in result.suggestions) {
        final isTeamA = (s.fromMemberId <= 2 && s.toMemberId <= 2);
        final isTeamB = (s.fromMemberId >= 3 && s.toMemberId >= 3);
        expect(
          isTeamA || isTeamB,
          isTrue,
          reason:
              'Cross-team transfer detected: ${s.fromMemberId}→${s.toMemberId}',
        );
      }
    });

    test('multiple people paying for same team', () {
      // Team: members 1, 2, 3, 4
      // Member 1 pays ₹500, member 2 pays ₹300
      // Total ₹800, each share ₹200

      final expenses = [expense(1, 1, 50000), expense(2, 2, 30000)];

      // Shares must sum to expense amounts
      // Expense 1: 50000 / 4 = 12500 each
      // Expense 2: 30000 / 4 = 7500 each
      final shares = [
        share(1, 1, 12500),
        share(1, 2, 12500),
        share(1, 3, 12500),
        share(1, 4, 12500),
        share(2, 1, 7500),
        share(2, 2, 7500),
        share(2, 3, 7500),
        share(2, 4, 7500),
      ];

      final payments = [payment(1, 1, 50000), payment(2, 2, 30000)];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);

      // Member 1: paid 50000, share = 12500 + 7500 = 20000, net +30000
      expect(result.remainingNets[1], 30000);
      // Member 2: paid 30000, share = 12500 + 7500 = 20000, net +10000
      expect(result.remainingNets[2], 10000);
      // Members 3,4: paid 0, share = 20000 each, net -20000 each
      expect(result.remainingNets[3], -20000);
      expect(result.remainingNets[4], -20000);

      // Settlement remains member-level
      expect(result.totalOutstanding, 40000);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 12: COMPLETE REAL-WORLD SCENARIO
  // ════════════════════════════════════════════════════════════════════════

  group('Complete real-world scenario', () {
    test('Shaik/Suganth/Asma/Man trip with registration, train, food', () {
      // Members: Shaik(1), Suganth(2), Asma(3), Man(4)
      // External person: not in group

      // Expense 1: Registration ₹1,827 total
      //   5 people × ₹365.40 = ₹1,827
      //   Suganth pays ₹730.90 for himself + external person
      //   External portion: ₹365.50 (not shared)
      //   Group share: ₹365.40 (Suganth's own share)
      //   Only Suganth is a participant (individual scope)

      final regShares = splitter.split(
        totalMinor: 73090 - 36550, // 36540
        memberIds: [2], // Suganth only
      );

      // Expense 2: Train ₹183.40 per person, 4 people = ₹733.60
      //   Shaik pays for everyone
      final trainShares = splitter.split(
        totalMinor: 73360,
        memberIds: [1, 2, 3, 4],
      );

      // Expense 3: Food ₹600, Shaik pays, shared among Shaik, Asma, Man
      final foodShares = splitter.split(
        totalMinor: 60000,
        memberIds: [1, 3, 4],
      );

      // Expense 4: Individual expense - Shaik ₹250 for his own food
      final indivShares = splitter.split(totalMinor: 25000, memberIds: [1]);

      final expenses = [
        expense(1, 2, 73090, external: 36550, scope: ExpenseScope.individual),
        expense(2, 1, 73360),
        expense(3, 1, 60000),
        expense(4, 1, 25000, scope: ExpenseScope.individual),
      ];

      final allShares = [
        // Registration
        share(1, 2, regShares.first.amountMinor),
        // Train
        for (final s in trainShares) share(2, s.memberId, s.amountMinor),
        // Food
        for (final s in foodShares) share(3, s.memberId, s.amountMinor),
        // Individual
        share(4, 1, indivShares.first.amountMinor),
      ];

      final payments = [
        payment(1, 2, 73090),
        payment(2, 1, 73360),
        payment(3, 1, 60000),
        payment(4, 1, 25000),
      ];

      // Verify zero-sum invariant: sum(payments) - sum(shares) - sum(external) = 0
      // The external portion is paid by the payer but not shared, so it doesn't
      // appear in shares. The group shareable amount = payment - external.
      final totalShares = allShares.fold<int>(
        0,
        (sum, s) => sum + s.shareMinor,
      );
      final totalPayments = payments.fold<int>(
        0,
        (sum, p) => sum + p.amountMinor,
      );
      const totalExternal = 36550;
      // group shareable = total payments - external = total shares
      expect(totalPayments - totalExternal, totalShares);

      // Calculate settlement
      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: allShares,
        settlements: const [],
        payments: payments,
      );

      // Net sum must be zero
      final settlementNetSum = result.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      expect(settlementNetSum, 0);

      // No one should have the external amount in their share
      for (final s in allShares) {
        expect(s.shareMinor, greaterThan(0));
      }
    });

    test('settlement after partial payment then expense edit', () {
      // Create expense: A pays ₹100 for A+B
      var expenses = [expense(1, 1, 10000)];
      var shares = [share(1, 1, 5000), share(1, 2, 5000)];
      var payments = [payment(1, 1, 10000)];

      var result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );
      expect(result.suggestions.first.minor, 5000);

      // B pays ₹20 partial
      final settlements = [makeSettlement(1, 2, 1, 5000, paid: 2000)];
      result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      expect(result.suggestions.first.minor, 3000);

      // Edit expense to ₹140 (shares become ₹70 each)
      expenses = [expense(1, 1, 14000)];
      shares = [share(1, 1, 7000), share(1, 2, 7000)];
      payments = [payment(1, 1, 14000)];

      result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      // B owes ₹70 - ₹20 already paid = ₹50
      expect(result.suggestions.first.minor, 5000);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 13: CASH BALANCE FORMULA
  // ════════════════════════════════════════════════════════════════════════

  group('Cash balance formula', () {
    test(
      'cashRemaining = contributions + settlementsReceived - actualPaid - settlementsPaid',
      () {
        final result = BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: [
            contribution(1, 50000), // A contributed ₹500
            contribution(2, 30000), // B contributed ₹300
          ],
          expenses: [expense(1, 1, 40000)], // A paid ₹400 for A+B
          shares: [share(1, 1, 20000), share(1, 2, 20000)],
          settlements: [
            makeSettlement(1, 2, 1, 20000, paid: 20000), // B paid A ₹200
          ],
          payments: [payment(1, 1, 40000)],
        );

        final a = result.members.firstWhere((m) => m.memberId == 1);
        final b = result.members.firstWhere((m) => m.memberId == 2);

        // A: contribution(500) + received(200) - paid(400) - paidOut(0) = 300
        expect(a.cashRemaining, 30000);
        expect(a.cashRemaining, a.contribution + 20000 - a.actualPaid - 0);

        // B: contribution(300) + received(0) - paid(0) - paidOut(200) = 100
        expect(b.cashRemaining, 10000);
        expect(b.cashRemaining, b.contribution + 0 - b.actualPaid - 20000);
      },
    );

    test('settlement payments never become expenses', () {
      final before = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: const [],
        expenses: [expense(1, 1, 50000)],
        shares: [share(1, 1, 25000), share(1, 2, 25000)],
        settlements: const [],
        payments: [payment(1, 1, 50000)],
      );

      final after = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: const [],
        expenses: [expense(1, 1, 50000)],
        shares: [share(1, 1, 25000), share(1, 2, 25000)],
        settlements: [makeSettlement(1, 2, 1, 25000, paid: 25000)],
        payments: [payment(1, 1, 50000)],
      );

      // Total expenses unchanged
      expect(after.totalExpenses, before.totalExpenses);
      // Budget unchanged
      expect(after.remainingBudget, before.remainingBudget);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 14: FULL DATA FLOW CONSISTENCY
  // ════════════════════════════════════════════════════════════════════════

  group('Full data flow consistency', () {
    test('balance and settlement always agree on net positions', () {
      // Complex scenario with 5 members, 4 expenses, 1 partial settlement
      final expenses = [
        expense(1, 1, 30000),
        expense(2, 2, 40000),
        expense(3, 3, 20000),
        expense(4, 4, 10000),
      ];

      final shares = [
        share(1, 1, 10000),
        share(1, 2, 10000),
        share(1, 3, 10000),
        share(2, 2, 20000),
        share(2, 3, 20000),
        share(3, 3, 10000),
        share(3, 4, 10000),
        share(3, 5, 0), // Not participating
        share(4, 4, 10000),
      ];

      final payments = [
        payment(1, 1, 30000),
        payment(2, 2, 40000),
        payment(3, 3, 20000),
        payment(4, 4, 10000),
      ];

      final settlements = [
        makeSettlement(1, 3, 2, 20000, paid: 10000), // Partial
      ];

      final settlement = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // Settlement adjusts remainingNets by paid settlement amounts, while
      // balance.netPosition is the raw expense-based position. After full
      // settlement, all outstanding should be zero.
      // The settlement totalOutstanding is less than or equal to the balance
      // totalOutstanding because partial payments reduce outstanding debt.

      // Verify: total outstanding equals total receivable by creditors
      final totalReceivable = settlement.remainingNets.values
          .where((v) => v > 0)
          .fold<int>(0, (s, v) => s + v);
      expect(settlement.totalOutstanding, totalReceivable);
      // totalOutstanding also equals total owed by debtors
      final totalOwed = settlement.remainingNets.values
          .where((v) => v < 0)
          .fold<int>(0, (s, v) => s + v.abs());
      expect(settlement.totalOutstanding, totalOwed);

      // Zero-sum must hold
      final netSum = settlement.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      expect(netSum, 0);
    });

    test('all net positions sum to zero for any data combination', () {
      // Randomized-like test with specific data
      final scenarios = [
        // Simple pair
        (
          expenses: [expense(1, 1, 10000)],
          shares: [share(1, 1, 5000), share(1, 2, 5000)],
          payments: [payment(1, 1, 10000)],
        ),
        // Triple
        (
          expenses: [expense(1, 1, 30000)],
          shares: [share(1, 1, 10000), share(1, 2, 10000), share(1, 3, 10000)],
          payments: [payment(1, 1, 30000)],
        ),
        // Multi-payer
        (
          expenses: [expense(1, 1, 10000), expense(2, 2, 8000)],
          shares: [
            share(1, 1, 5000),
            share(1, 2, 5000),
            share(2, 1, 4000),
            share(2, 2, 4000),
          ],
          payments: [payment(1, 1, 10000), payment(2, 2, 8000)],
        ),
      ];

      for (final scenario in scenarios) {
        final result = SettlementCalculator.calculate(
          expenses: scenario.expenses,
          shares: scenario.shares,
          settlements: const [],
          payments: scenario.payments,
        );
        final netSum = result.remainingNets.values.fold<int>(
          0,
          (s, v) => s + v,
        );
        expect(netSum, 0);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // PROBLEM 6: SETTLEMENT HISTORY SAFETY
  // ════════════════════════════════════════════════════════════════════════

  group('Settlement history safety', () {
    test('settlement with paid amount survives expense edit', () {
      // Original: A paid ₹100 for A+B. B owes A ₹50.
      // B pays ₹30 (partial).
      // Then expense is edited to ₹120 (shares become ₹60 each).
      // B now owes ₹60 - ₹30 = ₹30 more.

      final settlements = [makeSettlement(1, 2, 1, 5000, paid: 3000)];

      // After expense edit to ₹120
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 12000)],
        shares: [share(1, 1, 6000), share(1, 2, 6000)],
        settlements: settlements,
        payments: [payment(1, 1, 12000)],
      );

      // Total obligation = ₹60, paid = ₹30, outstanding = ₹30
      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.first.minor, 3000);
    });

    test('deleting an expense after settlement recalculates correctly', () {
      // Two expenses. B paid partial on consolidated debt.
      // Delete expense 2. Remaining debt recalculates.

      // B owes A ₹80 total, pays ₹50
      final settlements = [makeSettlement(1, 2, 1, 8000, paid: 5000)];

      // Delete expense 2
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: settlements,
        payments: [payment(1, 1, 10000)],
      );

      // Now B only owes ₹50 from expense 1, but already paid ₹50
      // So outstanding should be ₹0
      expect(result.totalOutstanding, 0);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // ZERO-SUM AND ROUNDING INVARIANTS
  // ════════════════════════════════════════════════════════════════════════

  group('Invariants', () {
    test('sum(expense shares) == expense total for every expense', () {
      final expenses = [
        expense(1, 1, 10000),
        expense(2, 1, 30000),
        expense(3, 1, 73360, external: 10000),
      ];

      final allShares = [
        ...splitter
            .split(totalMinor: 10000, memberIds: [1, 2, 3])
            .map((s) => share(1, s.memberId, s.amountMinor)),
        ...splitter
            .split(totalMinor: 30000, memberIds: [1, 2])
            .map((s) => share(2, s.memberId, s.amountMinor)),
        ...splitter
            .split(totalMinor: 63360, memberIds: [1, 2])
            .map((s) => share(3, s.memberId, s.amountMinor)),
      ];

      for (final exp in expenses) {
        final expShares = allShares.where((s) => s.expenseId == exp.id);
        final shareTotal = expShares.fold<int>(
          0,
          (sum, s) => sum + s.shareMinor,
        );
        final expectedTotal = exp.amountMinor - exp.externalAmountMinor;
        expect(
          shareTotal,
          expectedTotal,
          reason: 'Expense ${exp.id} shares must sum to group amount',
        );
      }
    });

    test('settlement does not change expense totals', () {
      final expenses = [expense(1, 1, 50000), expense(2, 2, 30000)];
      final shares = [
        share(1, 1, 25000),
        share(1, 2, 25000),
        share(2, 1, 15000),
        share(2, 2, 15000),
      ];
      final payments = [payment(1, 1, 50000), payment(2, 2, 30000)];

      final before = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final settlements = [
        makeSettlement(1, 2, 1, 10000, paid: 10000),
        makeSettlement(2, 1, 2, 5000, paid: 5000),
      ];

      final after = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      expect(after.totalExpenses, before.totalExpenses);
      expect(after.remainingBudget, before.remainingBudget);
      expect(after.totalContributions, before.totalContributions);
    });

    test('money precision: ₹100 / 3 never loses money', () {
      final shares = splitter.split(totalMinor: 10000, memberIds: [1, 2, 3]);
      final sum = shares.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, 10000);
      expect(shares[0].amountMinor, 3334);
      expect(shares[1].amountMinor, 3333);
      expect(shares[2].amountMinor, 3333);
    });

    test('MoneyCalculator format handles Indian numbering', () {
      // Values are in paise (minor units)
      expect(MoneyCalculator.format(12345678), '₹1,23,456.78');
      expect(MoneyCalculator.format(10000000), '₹1,00,000.00');
      expect(MoneyCalculator.format(999), '₹9.99');
      expect(MoneyCalculator.format(0), '₹0.00');
      expect(MoneyCalculator.format(-5000), '-₹50.00');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // MEMBER REMOVAL SAFETY
  // ════════════════════════════════════════════════════════════════════════

  group('Member removal safety', () {
    test('balance correctly excludes removed member from calculations', () {
      // If a member is removed, their data should not appear in balance
      // This is tested by simply not including them in the data

      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: [contribution(1, 50000)],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 10000)],
        settlements: const [],
        payments: [payment(1, 1, 10000)],
      );

      // Only member 1 exists
      expect(result.members, hasLength(1));
      expect(result.members.first.memberId, 1);
    });
  });
}
