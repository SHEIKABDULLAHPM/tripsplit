import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// Guards the team-aware settlement plan.
///
/// For multi-payer team expenses the plan must keep non-payer members within
/// their own team (they only owe their team's payer) and balance differences
/// between payers as cross-team edges. It must NOT fall back to the global
/// greedy nets, which map a member of one team onto a payer of another team
/// purely because their balances match.
void main() {
  final now = DateTime(2026, 9, 12);

  // Team 1 = {1, 2}, Team 2 = {3, 4}.
  final commonExpense = Expense(
    id: 101,
    tripId: 1,
    payerMemberId: 1,
    description: 'Common',
    amountMinor: 4000_00,
    scope: ExpenseScope.team,
    teamIds: [10, 20],
    teamId: 10,
    createdAt: now,
    updatedAt: now,
  );
  const equalShares = [
    ExpenseShare(id: 1, expenseId: 101, memberId: 1, shareMinor: 1000_00),
    ExpenseShare(id: 2, expenseId: 101, memberId: 2, shareMinor: 1000_00),
    ExpenseShare(id: 3, expenseId: 101, memberId: 3, shareMinor: 1000_00),
    ExpenseShare(id: 4, expenseId: 101, memberId: 4, shareMinor: 1000_00),
  ];
  const unbalancedPayments = [
    ExpensePayment(
      id: 1,
      expenseId: 101,
      memberId: 1,
      amountMinor: 2500_00,
      teamId: 10,
    ),
    ExpensePayment(
      id: 2,
      expenseId: 101,
      memberId: 3,
      amountMinor: 1500_00,
      teamId: 20,
    ),
  ];
  const teamMemberIds = {10: {1, 2}, 20: {3, 4}};

  SettlementResult plan({
    List<Expense>? expenses,
    List<ExpenseShare>? shares,
    List<ExpensePayment>? payments,
    List<Settlement>? settlements,
    Map<int, Set<int>>? teamIds,
  }) => SettlementCalculator.calculate(
    expenses: expenses ?? [commonExpense],
    shares: shares ?? equalShares,
    settlements: settlements ?? const [],
    payments: payments ?? unbalancedPayments,
    teamMemberIds: teamIds ?? teamMemberIds,
  );

  Set<String> describe(SettlementResult result) => result.suggestions
      .map((s) => '${s.fromMemberId}->${s.toMemberId}:${s.minor}')
      .toSet();

  group('Team-aware settlement plan', () {
    test(
      'non-payer members owe only their own team payer; payers balance '
      'between teams (no greedy cross-member edge 4->1)',
      () {
        final result = plan();

        expect(
          describe(result),
          {'2->1:100000', '4->3:100000', '3->1:50000'},
        );
        // Together they settle B (1,000) and D (1,000); the +500 payer edge
        // reflects A fronting more than Team 2's payer C.
        expect(result.totalOutstanding, 2500_00);
      },
    );

    test('without team context the greedy plan is still used', () {
      final result = SettlementCalculator.calculate(
        expenses: [commonExpense],
        shares: equalShares,
        settlements: const <Settlement>[],
        payments: unbalancedPayments,
      );

      expect(
        describe(result),
        {'2->1:100000', '4->1:50000', '4->3:50000'},
      );
      expect(result.totalOutstanding, 2000_00);
    });

    test('remaining nets reflect member-level positions after settlements',
        () {
      final result = plan();

      expect(result.remainingNets[1], 1500_00);
      expect(result.remainingNets[2], -1000_00);
      expect(result.remainingNets[3], 500_00);
      expect(result.remainingNets[4], -1000_00);
    });

    test('balanced multi-payer teams produce purely intra-team edges', () {
      // 10 members, 5 per team; A pays 2000 for Team 1, F pays 2000 for
      // Team 2; everyone shares equally (400 each).
      final shares = <ExpenseShare>[
        for (var i = 1; i <= 10; i++)
          ExpenseShare(
            id: i,
            expenseId: 101,
            memberId: i,
            shareMinor: 400_00,
          ),
      ];
      final payments = [
        const ExpensePayment(
          id: 1,
          expenseId: 101,
          memberId: 1,
          amountMinor: 2000_00,
          teamId: 10,
        ),
        const ExpensePayment(
          id: 2,
          expenseId: 101,
          memberId: 6,
          amountMinor: 2000_00,
          teamId: 20,
        ),
      ];
      final result = plan(
        shares: shares,
        payments: payments,
        teamIds: {10: {1, 2, 3, 4, 5}, 20: {6, 7, 8, 9, 10}},
      );

      final expected = <String>{
        for (final member in [2, 3, 4, 5]) '$member->1:40000',
        for (final member in [7, 8, 9, 10]) '$member->6:40000',
      };
      expect(describe(result), expected);
      // No cross-team edges and gross equals net debt for balanced teams.
      expect(result.totalOutstanding, 8 * 400_00);
    });

    test('single payer covering every team keeps direct edges (no payers to '
        'balance)', () {
      final result = plan(
        payments: [
          const ExpensePayment(
            id: 1,
            expenseId: 101,
            memberId: 1,
            amountMinor: 4000_00,
            teamId: 10,
          ),
        ],
      );

      expect(
        describe(result),
        {'2->1:100000', '3->1:100000', '4->1:100000'},
      );
      expect(result.totalOutstanding, 3000_00);
    });

    test('a legacy cross-team settlement never re-charges the payer', () {
      // Recorded under the old greedy plan: D already paid A 500 directly.
      final legacy = Settlement(
        id: 1,
        tripId: 1,
        fromMemberId: 4,
        toMemberId: 1,
        amountMinor: 500_00,
        amountPaidMinor: 500_00,
        note: null,
        settledAt: now,
        paidAt: now,
        updatedAt: now,
      );
      final result = plan(settlements: [legacy]);

      expect(
        describe(result),
        {'2->1:100000', '4->3:50000', '3->1:50000'},
      );
      // D still owes 500 of his original 1,000; the paid 500 is honoured.
      expect(result.totalOutstanding, 2000_00);

      final livingEdge = result.suggestions
          .where((s) => s.fromMemberId == 4)
          .single;
      expect(livingEdge.toMemberId, 3);
      expect(livingEdge.minor, 500_00);
    });

    test('paying every suggestion in full drains the plan to zero', () {
      final base = plan();
      final settlements = [
        for (final suggestion in base.suggestions)
          Settlement(
            id: suggestion.fromMemberId * 100 + suggestion.toMemberId,
            tripId: 1,
            fromMemberId: suggestion.fromMemberId,
            toMemberId: suggestion.toMemberId,
            amountMinor: suggestion.minor,
            amountPaidMinor: suggestion.minor,
            note: null,
            settledAt: now,
            paidAt: now,
            updatedAt: now,
          ),
      ];

      final result = plan(settlements: settlements);
      expect(result.suggestions, isEmpty);
      expect(result.totalOutstanding, 0);
      // But cash truly moved: payer positions still net to zero.
      expect(
        result.remainingNets.values.fold<int>(0, (sum, v) => sum + v),
        0,
      );
    });

    test('partial payment decays only the matching team edge', () {
      final partial = Settlement(
        id: 1,
        tripId: 1,
        fromMemberId: 4,
        toMemberId: 3,
        amountMinor: 1000_00,
        amountPaidMinor: 400_00,
        note: null,
        settledAt: now,
        paidAt: now,
        updatedAt: now,
      );
      final result = plan(settlements: [partial]);

      expect(
        describe(result),
        {'2->1:100000', '4->3:60000', '3->1:50000'},
      );
    });

    test('same-team payer plus generic payer never double-charges a member', () {
      // Team 10 = {1, 2, 3}. A pays ₹1,200 for Team 10; C also pays ₹800 as a
      // generic payer (not tied to a team). Shares are ₹667/₹667/₹666.
      const shares = [
        ExpenseShare(id: 1, expenseId: 101, memberId: 1, shareMinor: 667_00),
        ExpenseShare(id: 2, expenseId: 101, memberId: 2, shareMinor: 667_00),
        ExpenseShare(id: 3, expenseId: 101, memberId: 3, shareMinor: 666_00),
      ];
      const payments = [
        ExpensePayment(
          id: 1,
          expenseId: 101,
          memberId: 1,
          amountMinor: 1200_00,
          teamId: 10,
        ),
        ExpensePayment(
          id: 2,
          expenseId: 101,
          memberId: 3,
          amountMinor: 800_00,
        ),
      ];
      final result = plan(
        shares: shares,
        payments: payments,
        teamIds: {10: {1, 2, 3}},
      );

      // B's ₹667 share is split over both funders by how much each paid:
      // 1200/2000 × 667 = 400.20 and 800/2000 × 667 = 266.80. The payer
      // imbalance then closes C→A for the remaining 132.80. B is never
      // charged twice.
      expect(
        describe(result),
        {'2->1:40020', '2->3:26680', '3->1:13280'},
      );
      expect(result.totalOutstanding, 799_80);
      // And every member still lands exactly on their member-level net.
      expect(result.remainingNets[1], 533_00);
      expect(result.remainingNets[2], -667_00);
      expect(result.remainingNets[3], 134_00);
    });

    test('membership in both teams does not multiply obligations', () {
      // Member 3 belongs to Team 10 AND Team 20, and is also the Team 20
      // payer. Overlap must not re-charge anyone or distort the share split.
      final result = plan(
        teamIds: {10: {1, 2, 3}, 20: {3, 4}},
      );

      expect(
        describe(result),
        {'2->1:100000', '4->3:100000', '3->1:50000'},
      );
      expect(result.totalOutstanding, 2500_00);
    });

    test('participant removed from both teams still closes every position', () {
      // Member 2 was removed from Team 10 AFTER the expense (he keeps his
      // share). No team payer owns him: his share is split between both
      // funders, and the residual edge C→A closes the payers exactly.
      final result = plan(
        teamIds: {10: {1}, 20: {3, 4}},
      );

      expect(
        describe(result),
        {'2->1:62500', '2->3:37500', '4->3:100000', '3->1:87500'},
      );
      // Every member's suggestion flow equals their net position:
      // 1 receives 625 + 875 = 1500; 2 pays 1000; 3 receives
      // 375 + 1000 and pays 875 → net +500; 4 pays 1000.
      expect(result.remainingNets[1], 1500_00);
      expect(result.remainingNets[2], -1000_00);
      expect(result.remainingNets[3], 500_00);
      expect(result.remainingNets[4], -1000_00);
    });
  });
}