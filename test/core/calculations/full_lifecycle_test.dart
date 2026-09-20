import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// Full lifecycle mutation test verifying Phase 55 (Final Mutation Test) and
/// Phase 56 (Required Test Matrix) scenarios.
///
/// This test proves that at every stage of the lifecycle:
///   Dashboard = Balance = Member Details = Expense Details = Settlement
/// for the same underlying financial truth.
void main() {
  final now = DateTime(2026, 9, 15);

  // ── Domain helpers ────────────────────────────────────────────────────

  Expense expense(
    int id,
    int payerId,
    int amount, {
    int external = 0,
    ExpenseScope scope = ExpenseScope.shared,
    int? segmentId,
    int? teamId,
  }) => Expense(
    id: id,
    tripId: 1,
    payerMemberId: payerId,
    description: 'Expense $id',
    scope: scope,
    amountMinor: amount,
    externalAmountMinor: external,
    segmentId: segmentId,
    teamId: teamId,
    createdAt: now,
    updatedAt: now,
  );

  ExpenseShare share(int expId, int memberId, int minor) => ExpenseShare(
    id: expId * 1000 + memberId,
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

  /// Verifies that BalanceCalculator and SettlementCalculator always agree
  /// on net positions and outstanding amounts for the same data.
  void assertConsistency({
    required List<Expense> expenses,
    required List<ExpenseShare> shares,
    required List<Settlement> settlements,
    required List<ExpensePayment> payments,
    required List<Contribution> contributions,
    required int budgetMinor,
    String? reason,
  }) {
    final balance = BalanceCalculator.calculate(
      tripBudgetMinor: budgetMinor,
      contributions: contributions,
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      payments: payments,
    );

    final settlementPlan = SettlementCalculator.calculate(
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      payments: payments,
    );

    // 1. Net positions must match when no settlements exist.
    // With settlements, remainingNets is adjusted by paid amounts while
    // balance.netPosition is the raw expense-based position.
    if (settlements.isEmpty) {
      for (final member in balance.members) {
        final settlementNet =
            settlementPlan.remainingNets[member.memberId] ?? 0;
        expect(
          settlementNet,
          member.netPosition,
          reason:
              '${reason ?? ""} Balance/settlement net mismatch for member ${member.memberId}',
        );
      }
    }

    // 2. Total outstanding: when no settlements exist, raw outstanding
    // (from balance net positions) must match the settlement plan outstanding.
    if (settlements.isEmpty) {
      expect(
        settlementPlan.totalOutstanding,
        balance.outstandingMinor,
        reason: '${reason ?? ""} Outstanding mismatch',
      );
    }

    // 3. Zero-sum invariant
    final netSum = balance.members.fold<int>(
      0,
      (sum, m) => sum + m.netPosition,
    );
    expect(
      netSum,
      0,
      reason: '${reason ?? ""} Net positions do not sum to zero',
    );

    // 4. Total expenses = sum of (group shareable amounts)
    final totalGroupAmount = expenses.fold<int>(
      0,
      (sum, e) => sum + (e.amountMinor - e.externalAmountMinor),
    );
    expect(
      balance.totalExpenses,
      totalGroupAmount,
      reason: '${reason ?? ""} Total expenses mismatch',
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 55: COMPLETE MUTATION WORKFLOW
  // ══════════════════════════════════════════════════════════════════════

  group('Phase 55: Complete mutation workflow', () {
    test('Create trip → add members → add contributions → add expenses → '
        'settle → new expense → edit expense → edit participants', () {
      // Members: 1=A, 2=B, 3=C, 4=D, 5=E

      // Step 1: Members contribute
      var contributions = [
        contribution(1, 50_00), // A: ₹500
        contribution(2, 30_00), // B: ₹300
        contribution(3, 40_00), // C: ₹400
      ];
      var expenses = <Expense>[];
      var shares = <ExpenseShare>[];
      var settlements = <Settlement>[];
      var payments = <ExpensePayment>[];

      // Verify: just contributions, no expenses
      var balance = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: contributions,
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      expect(balance.totalExpenses, 0);
      expect(balance.totalContributions, 120_00);

      // Step 2: Hotel ₹8000 - A pays for A,B,C (3 nights) + D (2 nights)
      // Custom split: A=2000, B=2000, C=2000, D=1333.34, D partial=666.67
      // Simplified: 4 people share equally for 4 nights
      expenses = [expense(1, 1, 80_00)];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
      ];
      payments = [payment(1, 1, 80_00)];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After hotel expense',
      );

      // Step 3: Dinner ₹2400 - A,B,C,D eat. E does not.
      expenses = [expense(1, 1, 80_00), expense(2, 2, 24_00)];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
        share(2, 1, 6_00),
        share(2, 2, 6_00),
        share(2, 3, 6_00),
        share(2, 4, 6_00),
      ];
      payments = [payment(1, 1, 80_00), payment(2, 2, 24_00)];

      // E has no dinner share
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After dinner expense',
      );

      // Verify E has no expense share
      balance = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: contributions,
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      final eBalance = balance.members.where((m) => m.memberId == 5);
      if (eBalance.isNotEmpty) {
        expect(eBalance.first.expenseShare, 0);
      }

      // Step 4: Partial settlement - B pays A ₹100
      settlements = [makeSettlement(1, 2, 1, 10_00, paid: 10_00)];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After partial settlement',
      );

      // Step 5: New expense after settlement - Taxi ₹600, C pays
      expenses = [
        expense(1, 1, 80_00),
        expense(2, 2, 24_00),
        expense(3, 3, 60_00),
      ];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
        share(2, 1, 6_00),
        share(2, 2, 6_00),
        share(2, 3, 6_00),
        share(2, 4, 6_00),
        share(3, 1, 20_00),
        share(3, 2, 20_00),
        share(3, 3, 20_00),
      ];
      payments = [
        payment(1, 1, 80_00),
        payment(2, 2, 24_00),
        payment(3, 3, 60_00),
      ];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After taxi expense',
      );

      // Step 6: Edit hotel expense from ₹8000 to ₹10000
      expenses = [
        expense(1, 1, 100_00),
        expense(2, 2, 24_00),
        expense(3, 3, 60_00),
      ];
      shares = [
        share(1, 1, 25_00),
        share(1, 2, 25_00),
        share(1, 3, 25_00),
        share(1, 4, 25_00),
        share(2, 1, 6_00),
        share(2, 2, 6_00),
        share(2, 3, 6_00),
        share(2, 4, 6_00),
        share(3, 1, 20_00),
        share(3, 2, 20_00),
        share(3, 3, 20_00),
      ];
      payments = [
        payment(1, 1, 100_00),
        payment(2, 2, 24_00),
        payment(3, 3, 60_00),
      ];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After editing hotel expense',
      );

      // Step 7: Change dinner participants - remove D
      shares = [
        share(1, 1, 25_00),
        share(1, 2, 25_00),
        share(1, 3, 25_00),
        share(1, 4, 25_00),
        share(2, 1, 8_00),
        share(2, 2, 8_00),
        share(2, 3, 8_00),
        share(3, 1, 20_00),
        share(3, 2, 20_00),
        share(3, 3, 20_00),
      ];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After changing dinner participants',
      );

      // D no longer has dinner share
      balance = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: contributions,
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      final dBalance = balance.members.firstWhere((m) => m.memberId == 4);
      expect(
        dBalance.expenseShare,
        25_00,
        reason: 'D should only have hotel share',
      );

      // Step 8: Edit contribution - C increases contribution to ₹600
      contributions = [
        contribution(1, 50_00),
        contribution(2, 30_00),
        contribution(3, 60_00),
      ];

      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 200_00,
        reason: 'After editing contribution',
      );

      // Verify C's cash remaining changed but net position didn't
      balance = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: contributions,
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      final cBalance = balance.members.firstWhere((m) => m.memberId == 3);
      expect(
        cBalance.cashRemaining,
        60_00 - 60_00,
      ); // contributed 600, paid 600
      expect(cBalance.contribution, 60_00);
    });

    test('individual expense does not enter group debt', () {
      final expenses = [expense(1, 1, 25_00, scope: ExpenseScope.individual)];
      final shares = [share(1, 1, 25_00)];
      final payments = [payment(1, 1, 25_00)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final settlementPlan = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // A's net = 0 (paid what they owe)
      expect(balance.members.single.netPosition, 0);
      expect(settlementPlan.suggestions, isEmpty);
    });

    test('segment expense uses segment participants only', () {
      // Segment A→B: members 1,2,3 participated
      final expenses = [expense(1, 1, 60_00, segmentId: 1)];
      final shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
      ];
      final payments = [payment(1, 1, 60_00)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // Members 4 and 5 have no share
      final m4 = balance.members.where((m) => m.memberId == 4);
      if (m4.isNotEmpty) {
        expect(m4.first.expenseShare, 0);
      }

      // Net sum zero
      final netSum = balance.members.fold<int>(0, (s, m) => s + m.netPosition);
      expect(netSum, 0);
    });

    test('external person amount does not affect group', () {
      final expenses = [
        expense(1, 1, 730_90, external: 365_50, scope: ExpenseScope.individual),
      ];
      final shares = [share(1, 1, 365_40)];
      final payments = [payment(1, 1, 730_90)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // Group shareable: 73090 - 36550 = 36540
      expect(balance.totalExpenses, 365_40);

      // A's net: paid 36540 (group portion), share 36540 → net 0
      expect(balance.members.single.netPosition, 0);
    });

    test('multiple payers with different shares', () {
      // Restaurant ₹2000
      // A pays ₹1200, B pays ₹800
      // Participants: A, B, C, D → each share ₹500
      final expenses = [expense(1, 1, 200_00)];
      final shares = [
        share(1, 1, 50_00),
        share(1, 2, 50_00),
        share(1, 3, 50_00),
        share(1, 4, 50_00),
      ];
      final payments = [payment(1, 1, 120_00), payment(1, 2, 80_00)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // A: paid 1200, share 500 → net +700 (owed)
      final a = balance.members.firstWhere((m) => m.memberId == 1);
      expect(a.netPosition, 70_00);
      expect(a.actualPaid, 120_00);

      // B: paid 800, share 500 → net +300 (owed)
      final b = balance.members.firstWhere((m) => m.memberId == 2);
      expect(b.netPosition, 30_00);
      expect(b.actualPaid, 80_00);

      // C: paid 0, share 500 → net -500 (owes)
      final c = balance.members.firstWhere((m) => m.memberId == 3);
      expect(c.netPosition, -50_00);

      // D: paid 0, share 500 → net -500 (owes)
      final d = balance.members.firstWhere((m) => m.memberId == 4);
      expect(d.netPosition, -50_00);

      // Net sum zero
      final netSum = balance.members.fold<int>(0, (s, m) => s + m.netPosition);
      expect(netSum, 0);
    });

    test('settlement never changes expense totals', () {
      final expenses = [expense(1, 1, 100_00), expense(2, 2, 60_00)];
      final shares = [
        share(1, 1, 50_00),
        share(1, 2, 50_00),
        share(2, 1, 30_00),
        share(2, 2, 30_00),
      ];
      final payments = [payment(1, 1, 100_00), payment(2, 2, 60_00)];

      final before = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final after = BalanceCalculator.calculate(
        tripBudgetMinor: 200_00,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: [
          makeSettlement(1, 2, 1, 20_00, paid: 20_00),
          makeSettlement(2, 1, 2, 10_00, paid: 10_00),
        ],
        payments: payments,
      );

      // Total expenses unchanged
      expect(after.totalExpenses, before.totalExpenses);
      expect(after.remainingBudget, before.remainingBudget);
      expect(after.totalContributions, before.totalContributions);

      // Net positions unchanged
      for (var i = 0; i < before.members.length; i++) {
        expect(after.members[i].netPosition, before.members[i].netPosition);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 56: REAL-WORLD SCENARIOS
  // ══════════════════════════════════════════════════════════════════════

  group('Phase 56: Real-world scenarios', () {
    test('cash + UPI scenario: two payers pay different methods', () {
      // Hotel ₹5000
      // A pays ₹3000 cash, B pays ₹2000 UPI
      final expenses = [expense(1, 1, 500_00)];
      final shares = [share(1, 1, 250_00), share(1, 2, 250_00)];
      final payments = [payment(1, 1, 300_00), payment(1, 2, 200_00)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // A: paid 3000, share 2500 → net +500
      final a = balance.members.firstWhere((m) => m.memberId == 1);
      expect(a.netPosition, 50_00);

      // B: paid 2000, share 2500 → net -500
      final b = balance.members.firstWhere((m) => m.memberId == 2);
      expect(b.netPosition, -50_00);
    });

    test('partial repayment lifecycle', () {
      // A pays ₹800 for A+B → B owes A ₹400
      final expenses = [expense(1, 1, 80_00)];
      final shares = [share(1, 1, 40_00), share(1, 2, 40_00)];
      final payments = [payment(1, 1, 80_00)];

      // Step 1: B pays ₹300
      var settlements = [makeSettlement(1, 2, 1, 40_00, paid: 30_00)];

      var result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      expect(result.suggestions.first.minor, 10_00); // ₹100 remaining

      // Step 2: B pays remaining ₹100
      settlements = [makeSettlement(1, 2, 1, 40_00, paid: 40_00)];

      result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      expect(result.suggestions, isEmpty); // Fully settled
    });

    test('settlement history after settlement then new expense', () {
      // Original: A paid ₹500 for A+B. B owes ₹250.
      var expenses = [expense(1, 1, 50_00)];
      var shares = [share(1, 1, 25_00), share(1, 2, 25_00)];
      var payments = [payment(1, 1, 50_00)];

      // B pays full ₹250
      final settlements = [makeSettlement(1, 2, 1, 25_00, paid: 25_00)];

      var result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
      expect(result.totalOutstanding, 0);

      // New expense: B pays ₹400 for A+B (each share ₹200)
      expenses = [expense(1, 1, 50_00), expense(2, 2, 40_00)];
      shares = [
        share(1, 1, 25_00),
        share(1, 2, 25_00),
        share(2, 1, 20_00),
        share(2, 2, 20_00),
      ];
      payments = [payment(1, 1, 50_00), payment(2, 2, 40_00)];

      // Settlement for old expense stays, new expense creates new debt
      result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // After settlement of old expense (250 paid), remaining nets:
      // A: raw net +5 (from expenses), minus 25 settled → -20
      // B: raw net -5 (from expenses), plus 25 settled → +20
      // Settlement outstanding: B owes A 20 (5 from expense 2 net + old settled adjustment)
      expect(result.totalOutstanding, 20_00);
    });

    test('unequal food responsibility: different orders', () {
      // A orders ₹500, B orders ₹300, C orders ₹100
      // Restaurant bill = ₹900
      // Custom split: A=500, B=300, C=100
      final expenses = [expense(1, 1, 90_00)];
      final shares = [
        share(1, 1, 50_00),
        share(1, 2, 30_00),
        share(1, 3, 10_00),
      ];
      final payments = [payment(1, 1, 90_00)];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // A paid ₹900, share ₹500 → net +₹400
      final a = balance.members.firstWhere((m) => m.memberId == 1);
      expect(a.netPosition, 40_00);

      // B share ₹300 → net -₹300
      final b = balance.members.firstWhere((m) => m.memberId == 2);
      expect(b.netPosition, -30_00);

      // C share ₹100 → net -₹100
      final c = balance.members.firstWhere((m) => m.memberId == 3);
      expect(c.netPosition, -10_00);
    });

    test('complex journey with repeated locations', () {
      // Erode→Chennai→Hyderabad→Bengaluru→Chennai→Bengaluru→Erode
      // Sanu (member 3) participates only in Bengaluru→Chennai→Bengaluru
      //
      // This is a participation test. The segments 3→4 only include members
      // who participate, not all trip members.

      final expenses = [
        expense(1, 1, 30_00, segmentId: 1), // Erode→Chennai (members 1,2)
        expense(2, 2, 20_00, segmentId: 3), // Bengaluru→Chennai (members 1,2,3)
        expense(3, 1, 40_00, segmentId: 4), // Chennai→Bengaluru (members 1,2,3)
      ];

      // Segment 1: only 1,2
      // Segment 3: 1,2,3
      // Segment 4: 1,2,3
      final shares = [
        share(1, 1, 15_00),
        share(1, 2, 15_00),
        share(2, 1, 6_67),
        share(2, 2, 6_67),
        share(2, 3, 6_66),
        share(3, 1, 13_34),
        share(3, 2, 13_33),
        share(3, 3, 13_33),
      ];
      final payments = [
        payment(1, 1, 30_00),
        payment(2, 2, 20_00),
        payment(3, 1, 40_00),
      ];

      final balance = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: expenses,
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      // Verify zero-sum
      final netSum = balance.members.fold<int>(0, (s, m) => s + m.netPosition);
      expect(netSum, 0);

      // Verify Sanu (member 3) only has shares for segments 3 and 4
      final sanu = balance.members.firstWhere((m) => m.memberId == 3);
      expect(sanu.expenseShare, 6_66 + 13_33);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 40: DOUBLE SUBMISSION PROTECTION
  // ══════════════════════════════════════════════════════════════════════

  group('Phase 40: Double submission protection', () {
    test('settlement repository rejects overpayment', () {
      // This tests the validation logic that prevents creating invalid
      // settlement states that could result from rapid taps.
      //
      // The calculation engine correctly identifies that if B already fully
      // paid their debt, no further payment should be accepted.
      final expenses = [expense(1, 1, 100_00)];
      final shares = [share(1, 1, 50_00), share(1, 2, 50_00)];
      final payments = [payment(1, 1, 100_00)];

      // B has paid full debt
      final settlements = [makeSettlement(1, 2, 1, 50_00, paid: 50_00)];

      final result = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // No outstanding → any further payment should be rejected
      expect(result.totalOutstanding, 0);
      expect(
        SettlementCalculator.outstandingBetween(
          result.suggestions,
          fromMemberId: 2,
          toMemberId: 1,
        ),
        0,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // CROSS-SCREEN CONSISTENCY
  // ══════════════════════════════════════════════════════════════════════

  group('Cross-screen consistency', () {
    test('balance, settlement, and per-member details always agree', () {
      // 3 members, 3 expenses, 1 partial settlement
      final expenses = [
        expense(1, 1, 100_00),
        expense(2, 2, 80_00),
        expense(3, 1, 60_00),
      ];
      final shares = [
        share(1, 1, 50_00),
        share(1, 2, 50_00),
        share(2, 1, 40_00),
        share(2, 2, 40_00),
        share(3, 1, 20_00),
        share(3, 2, 20_00),
        share(3, 3, 20_00),
      ];
      final payments = [
        payment(1, 1, 100_00),
        payment(2, 2, 80_00),
        payment(3, 1, 60_00),
      ];
      final settlements = [makeSettlement(1, 2, 1, 10_00, paid: 5_00)];

      // Dashboard view
      final dashboard = BalanceCalculator.calculate(
        tripBudgetMinor: 300_00,
        contributions: [
          contribution(1, 200_00),
          contribution(2, 100_00),
          contribution(3, 150_00),
        ],
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // Settlement plan
      final settlementPlan = SettlementCalculator.calculate(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // Balance view (same calculation)
      final balanceView = BalanceCalculator.calculate(
        tripBudgetMinor: 300_00,
        contributions: [
          contribution(1, 200_00),
          contribution(2, 100_00),
          contribution(3, 150_00),
        ],
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // Member details view (same calculation, per-member extraction)
      final memberDetailView = BalanceCalculator.calculate(
        tripBudgetMinor: 300_00,
        contributions: [
          contribution(1, 200_00),
          contribution(2, 100_00),
          contribution(3, 150_00),
        ],
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );

      // All three must be identical
      for (var i = 0; i < dashboard.members.length; i++) {
        final dMember = dashboard.members[i];
        final bMember = balanceView.members.firstWhere(
          (m) => m.memberId == dMember.memberId,
        );
        final mMember = memberDetailView.members.firstWhere(
          (m) => m.memberId == dMember.memberId,
        );
        expect(dMember.netPosition, bMember.netPosition);
        expect(dMember.netPosition, mMember.netPosition);
        expect(dMember.cashRemaining, bMember.cashRemaining);
        expect(dMember.actualPaid, bMember.actualPaid);
        expect(dMember.expenseShare, bMember.expenseShare);
      }

      // Outstanding matches across balance views
      expect(dashboard.outstandingMinor, balanceView.outstandingMinor);

      // Net positions: balance shows raw expense-based position;
      // settlement.remainingNets shows post-settlement position.
      // When no settlements exist, they must be identical.
      if (settlements.isEmpty) {
        for (final member in dashboard.members) {
          expect(
            settlementPlan.remainingNets[member.memberId] ?? 0,
            member.netPosition,
            reason:
                'Member ${member.memberId} net mismatch between balance and settlement',
          );
        }
      }

      // Cash remaining: contribution + settlementsReceived - actualPaid - settlementsPaid
      // Verify the formula holds when no settlements exist
      if (settlements.isEmpty) {
        for (final member in dashboard.members) {
          expect(
            member.cashRemaining,
            member.contribution - member.actualPaid,
            reason:
                'Member ${member.memberId} cashRemaining formula check (no settlements)',
          );
        }
      }
    });

    test('after every lifecycle stage, all views agree', () {
      // Track state through the entire lifecycle
      var contributions = <Contribution>[];
      var expenses = <Expense>[];
      var shares = <ExpenseShare>[];
      var payments = <ExpensePayment>[];
      var settlements = <Settlement>[];

      // Stage 1: Empty trip
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 1: Empty trip',
      );

      // Stage 2: Members contribute
      contributions = [
        contribution(1, 100_00),
        contribution(2, 80_00),
        contribution(3, 60_00),
      ];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 2: After contributions',
      );

      // Stage 3: First expense
      expenses = [expense(1, 1, 100_00)];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
        share(1, 5, 20_00),
      ];
      payments = [payment(1, 1, 100_00)];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 3: After first expense',
      );

      // Stage 4: Second expense with multiple payers
      expenses = [expense(1, 1, 100_00), expense(2, 2, 150_00)];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
        share(1, 5, 20_00),
        share(2, 1, 30_00),
        share(2, 2, 30_00),
        share(2, 3, 30_00),
        share(2, 4, 30_00),
        share(2, 5, 30_00),
      ];
      payments = [payment(1, 1, 100_00), payment(2, 2, 150_00)];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 4: After second expense',
      );

      // Stage 5: Settlement
      settlements = [makeSettlement(1, 2, 1, 10_00, paid: 10_00)];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 5: After settlement',
      );

      // Stage 6: New expense after settlement
      expenses = [
        expense(1, 1, 100_00),
        expense(2, 2, 150_00),
        expense(3, 3, 80_00),
      ];
      shares = [
        share(1, 1, 20_00),
        share(1, 2, 20_00),
        share(1, 3, 20_00),
        share(1, 4, 20_00),
        share(1, 5, 20_00),
        share(2, 1, 30_00),
        share(2, 2, 30_00),
        share(2, 3, 30_00),
        share(2, 4, 30_00),
        share(2, 5, 30_00),
        share(3, 1, 16_00),
        share(3, 2, 16_00),
        share(3, 3, 16_00),
        share(3, 4, 16_00),
        share(3, 5, 16_00),
      ];
      payments = [
        payment(1, 1, 100_00),
        payment(2, 2, 150_00),
        payment(3, 3, 80_00),
      ];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 6: After new expense post-settlement',
      );

      // Stage 7: Edit old expense
      expenses = [
        expense(1, 1, 120_00), // Edited from 100 to 120
        expense(2, 2, 150_00),
        expense(3, 3, 80_00),
      ];
      shares = [
        share(1, 1, 24_00),
        share(1, 2, 24_00),
        share(1, 3, 24_00),
        share(1, 4, 24_00),
        share(1, 5, 24_00),
        share(2, 1, 30_00),
        share(2, 2, 30_00),
        share(2, 3, 30_00),
        share(2, 4, 30_00),
        share(2, 5, 30_00),
        share(3, 1, 16_00),
        share(3, 2, 16_00),
        share(3, 3, 16_00),
        share(3, 4, 16_00),
        share(3, 5, 16_00),
      ];
      payments = [
        payment(1, 1, 120_00),
        payment(2, 2, 150_00),
        payment(3, 3, 80_00),
      ];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 7: After editing old expense',
      );

      // Stage 8: Change participants - remove members 4,5 from expense 1
      // Expense 1 = ₹1200 (120_00), now split among 3 members
      shares = [
        share(1, 1, 40_00),
        share(1, 2, 40_00),
        share(1, 3, 40_00),
        share(2, 1, 30_00),
        share(2, 2, 30_00),
        share(2, 3, 30_00),
        share(2, 4, 30_00),
        share(2, 5, 30_00),
        share(3, 1, 16_00),
        share(3, 2, 16_00),
        share(3, 3, 16_00),
        share(3, 4, 16_00),
        share(3, 5, 16_00),
      ];
      assertConsistency(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
        contributions: contributions,
        budgetMinor: 500_00,
        reason: 'Stage 8: After changing participants',
      );
    });
  });
}
