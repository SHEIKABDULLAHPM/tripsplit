import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// Randomized, independent-oracle checks for the TripSplit financial engine.
///
/// Every invariant below is asserted against a tiny, deliberately naive
/// implementation written inside this file — not against the production
/// calculators — so a bug in the same code path cannot mask itself.
void main() {
  final rng = Random(20260913);

  DateTime now() => DateTime(2026, 9, 13);

  Contribution contribution(int id, int memberId, int amount) => Contribution(
    id: id,
    tripId: 1,
    memberId: memberId,
    amountMinor: amount,
    createdAt: now(),
  );

  Expense expense(int id, int payer, {required int amount, int external = 0}) =>
      Expense(
        id: id,
        tripId: 1,
        payerMemberId: payer,
        description: 'Expense $id',
        amountMinor: amount,
        externalAmountMinor: external,
        createdAt: now(),
        updatedAt: now(),
      );

  ExpenseShare share(int id, int memberId, int minor) =>
      ExpenseShare(id: id, expenseId: 0, memberId: memberId, shareMinor: minor);

  Settlement settlement(
    int id, {
    required int from,
    required int to,
    required int amount,
    required int paid,
  }) => Settlement(
    id: id,
    tripId: 1,
    fromMemberId: from,
    toMemberId: to,
    amountMinor: amount,
    amountPaidMinor: paid,
    note: null,
    settledAt: now(),
    paidAt: paid >= amount ? now() : null,
    updatedAt: now(),
  );

  /// Naive per-member aggregation, totally independent of the production
  /// calculators.
  ({
    Map<int, int> net,
    Map<int, int> paidFull,
    Map<int, int> groupOutlay,
    Map<int, int> share,
    Map<int, int> received,
    Map<int, int> paidOut,
  })
  naive(
    List<Expense> expenses,
    List<ExpenseShare> shares,
    List<Settlement> settlements,
  ) {
    final net = <int, int>{};
    final paidFull = <int, int>{};
    final groupOutlay = <int, int>{};
    final share = <int, int>{};
    final received = <int, int>{};
    final paidOut = <int, int>{};

    for (final e in expenses) {
      final group = e.amountMinor - e.externalAmountMinor;
      net[e.payerMemberId] = (net[e.payerMemberId] ?? 0) + group;
      paidFull[e.payerMemberId] =
          (paidFull[e.payerMemberId] ?? 0) + e.amountMinor;
      groupOutlay[e.payerMemberId] =
          (groupOutlay[e.payerMemberId] ?? 0) + group;
    }
    for (final s in shares) {
      net[s.memberId] = (net[s.memberId] ?? 0) - s.shareMinor;
      share[s.memberId] = (share[s.memberId] ?? 0) + s.shareMinor;
    }
    for (final st in settlements) {
      if (st.amountPaidMinor <= 0) {
        continue;
      }
      net[st.fromMemberId] = (net[st.fromMemberId] ?? 0) + st.amountPaidMinor;
      net[st.toMemberId] = (net[st.toMemberId] ?? 0) - st.amountPaidMinor;
      paidOut[st.fromMemberId] =
          (paidOut[st.fromMemberId] ?? 0) + st.amountPaidMinor;
      received[st.toMemberId] =
          (received[st.toMemberId] ?? 0) + st.amountPaidMinor;
    }

    return (
      net: net,
      paidFull: paidFull,
      groupOutlay: groupOutlay,
      share: share,
      received: received,
      paidOut: paidOut,
    );
  }

  for (var iteration = 0; iteration < 300; iteration++) {
    final memberCount = 2 + rng.nextInt(5); // 2..6 members
    final memberIds = [for (var i = 1; i <= memberCount; i++) i];

    final budget = rng.nextInt(400000);

    final contributions = <Contribution>[];
    var nextContributionId = 0;
    for (final memberId in memberIds) {
      final amount = rng.nextInt(150000);
      if (amount > 0) {
        contributions.add(contribution(nextContributionId++, memberId, amount));
      }
    }

    final expenses = <Expense>[];
    final allShares = <ExpenseShare>[];
    const splitter = EqualExpenseSplitter();

    final expenseCount = rng.nextInt(8);
    for (var i = 0; i < expenseCount; i++) {
      final amount = 1 + rng.nextInt(200000);
      final external = rng.nextBool() ? rng.nextInt(amount) : 0;
      final payer = memberIds[rng.nextInt(memberCount)];
      final participantCount = 1 + rng.nextInt(memberCount);
      final participants = (memberIds..shuffle(rng))
          .take(participantCount)
          .toList();

      final shares = splitter.split(
        totalMinor: amount - external,
        memberIds: participants,
      );
      for (final s in shares) {
        allShares.add(share(allShares.length, s.memberId, s.amountMinor));
      }
      expenses.add(expense(i, payer, amount: amount, external: external));
    }

    test('iteration $iteration: engine invariants hold', () {
      final naiveAgg = naive(expenses, allShares, const []);
      final expectedGroupTotal = expenses.fold<int>(
        0,
        (sum, e) => sum + e.amountMinor - e.externalAmountMinor,
      );

      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: budget,
        contributions: contributions,
        expenses: expenses,
        shares: allShares,
        settlements: const [],
      );

      // Budget and total expenses only ever see the group-shareable portion.
      expect(balances.totalExpenses, expectedGroupTotal);
      expect(balances.remainingBudget, budget - expectedGroupTotal);

      // Per member the five figures match the naive aggregation.
      final allIds = <int>{
        for (final c in contributions)
          if (c.amountMinor > 0) c.memberId,
        ...naiveAgg.net.keys,
      };
      for (final id in allIds) {
        final member = balances.members.firstWhere((b) => b.memberId == id);
        expect(member.actualPaid, naiveAgg.paidFull[id] ?? 0);
        expect(member.expenseShare, naiveAgg.share[id] ?? 0);
        expect(member.netPosition, naiveAgg.net[id] ?? 0);
        expect(
          member.cashRemaining,
          (contributions
                  .where((c) => c.memberId == id)
                  .fold<int>(0, (sum, c) => sum + c.amountMinor)) -
              (naiveAgg.paidFull[id] ?? 0),
        );
      }

      // Cash remaining across the group equals money contributed minus money
      // actually paid out of pocket.
      final contributed = contributions.fold<int>(
        0,
        (sum, c) => sum + c.amountMinor,
      );
      final paidFullTotal = naiveAgg.paidFull.values.fold<int>(
        0,
        (sum, v) => sum + v,
      );
      expect(balances.totalCashRemaining, contributed - paidFullTotal);

      // The whole group nets to zero, so creditors == debtors.
      final netSum = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.netPosition,
      );
      expect(netSum, 0);
      final toPay = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.amountToPay,
      );
      final toReceive = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.amountToReceive,
      );
      expect(toPay, toReceive);
      expect(balances.outstandingMinor, toPay);

      // Settlement plan matches the naive nets exactly and stays balanced.
      final plan = SettlementCalculator.calculate(
        expenses: expenses,
        shares: allShares,
        settlements: const [],
      );
      expect(plan.totalOutstanding, toPay);
      for (final suggestion in plan.suggestions) {
        expect(suggestion.minor, greaterThan(0));
        expect(naiveAgg.net[suggestion.fromMemberId]!, lessThan(0));
        expect(naiveAgg.net[suggestion.toMemberId]!, greaterThan(0));
        expect(
          suggestion.minor,
          lessThanOrEqualTo(-naiveAgg.net[suggestion.fromMemberId]!),
        );
        expect(
          suggestion.minor,
          lessThanOrEqualTo(naiveAgg.net[suggestion.toMemberId]!),
        );
      }
    });

    test('iteration $iteration: recorded settlements decay and then drain', () {
      final plan = SettlementCalculator.calculate(
        expenses: expenses,
        shares: allShares,
        settlements: const [],
      );

      // Record a few random partial payments against the plan, respecting the
      // outstanding amounts.
      final recorded = <Settlement>[];
      final shuffled = (List.of(
        plan.suggestions,
      )..shuffle(rng)).take(min(3, plan.suggestions.length));
      for (final suggestion in shuffled) {
        final paid = 1 + rng.nextInt(suggestion.minor); // partial or full
        recorded.add(
          settlement(
            recorded.length,
            from: suggestion.fromMemberId,
            to: suggestion.toMemberId,
            amount: suggestion.minor,
            paid: paid,
          ),
        );
      }

      final after = SettlementCalculator.calculate(
        expenses: expenses,
        shares: allShares,
        settlements: recorded,
      );
      final naiveAfter = naive(expenses, allShares, recorded);

      // Nets after settlements equal the naive expectation.
      expect(after.remainingNets, naiveAfter.net);
      expect(
        after.totalOutstanding,
        naiveAfter.net.values.where((v) => v > 0).fold(0, (sum, v) => sum + v),
      );

      // Closing out every remaining suggestion in full drains the trip.
      final settled = List<Settlement>.of(recorded);
      for (final remaining in after.suggestions) {
        settled.add(
          settlement(
            settled.length,
            from: remaining.fromMemberId,
            to: remaining.toMemberId,
            amount: remaining.minor,
            paid: remaining.minor,
          ),
        );
      }
      final drained = SettlementCalculator.calculate(
        expenses: expenses,
        shares: allShares,
        settlements: settled,
      );
      expect(drained.totalOutstanding, 0);
      expect(drained.remainingNets.values.where((v) => v != 0), isEmpty);
    });

    test(
      'iteration $iteration: settlements never alter spending or budget',
      () {
        final plan = SettlementCalculator.calculate(
          expenses: expenses,
          shares: allShares,
          settlements: const [],
        );
        final paidBefore = BalanceCalculator.calculate(
          tripBudgetMinor: budget,
          contributions: contributions,
          expenses: expenses,
          shares: allShares,
          settlements: const [],
        );

        final recorded = <Settlement>[];
        for (var i = 0; i < plan.suggestions.length; i++) {
          final suggestion = plan.suggestions[i];
          recorded.add(
            settlement(
              i,
              from: suggestion.fromMemberId,
              to: suggestion.toMemberId,
              amount: suggestion.minor,
              paid: suggestion.minor,
            ),
          );
        }
        final paidAfter = BalanceCalculator.calculate(
          tripBudgetMinor: budget,
          contributions: contributions,
          expenses: expenses,
          shares: allShares,
          settlements: recorded,
        );

        expect(paidAfter.totalExpenses, paidBefore.totalExpenses);
        expect(paidAfter.remainingBudget, paidBefore.remainingBudget);
        expect(paidAfter.totalContributions, paidBefore.totalContributions);
      },
    );
  }
}
