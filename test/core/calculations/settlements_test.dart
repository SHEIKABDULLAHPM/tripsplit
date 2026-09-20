import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

void main() {
  final now = DateTime(2026, 9, 12);

  Expense expense(
    int id,
    int payerId,
    int amountMinor, {
    int externalAmountMinor = 0,
  }) => Expense(
    id: id,
    tripId: 1,
    payerMemberId: payerId,
    description: 'Expense $id',
    amountMinor: amountMinor,
    externalAmountMinor: externalAmountMinor,
    createdAt: now,
    updatedAt: now,
  );

  ExpenseShare share(int expenseId, int memberId, int shareMinor) =>
      ExpenseShare(
        id: expenseId * 100 + memberId,
        expenseId: expenseId,
        memberId: memberId,
        shareMinor: shareMinor,
      );

  Settlement settlement(
    int id,
    int fromId,
    int toId,
    int amountMinor, {
    int paidMinor = 0,
  }) => Settlement(
    id: id,
    tripId: 1,
    fromMemberId: fromId,
    toMemberId: toId,
    amountMinor: amountMinor,
    amountPaidMinor: paidMinor,
    note: null,
    settledAt: now,
    paidAt: paidMinor >= amountMinor ? now : null,
    updatedAt: now,
  );

  group('SettlementCalculator.statusOf', () {
    test('grades outstanding, partial and paid settlements', () {
      expect(
        SettlementCalculator.statusOf(amountMinor: 36540, amountPaidMinor: 0),
        SettlementStatus.outstanding,
      );
      expect(
        SettlementCalculator.statusOf(
          amountMinor: 36540,
          amountPaidMinor: 20000,
        ),
        SettlementStatus.partial,
      );
      expect(
        SettlementCalculator.statusOf(
          amountMinor: 36540,
          amountPaidMinor: 36540,
        ),
        SettlementStatus.paid,
      );
    });
  });

  group('SettlementCalculator.calculate', () {
    test('produces no suggestions when everyone is balanced', () {
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 5000)],
        shares: [share(1, 1, 5000)],
        settlements: const [],
      );

      expect(result.suggestions, isEmpty);
      expect(result.totalOutstanding, 0);
    });

    test('suggests a single transfer for a simple debtor/creditor pair', () {
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 5000)],
        shares: [share(1, 2, 5000)],
        settlements: const [],
      );

      expect(result.suggestions, hasLength(1));
      final suggestion = result.suggestions.single;
      expect(suggestion.fromMemberId, 2);
      expect(suggestion.toMemberId, 1);
      expect(suggestion.minor, 5000);
    });

    test('minimizes the number of transfers', () {
      // A paid a 1000 share for B (B owes A 1000) and C paid 2000 shared
      // half with A (A owes C 1000): settlement needs exactly two transfers.
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 2000), expense(2, 3, 4000)],
        shares: [
          share(1, 1, 1000),
          share(1, 2, 1000),
          share(2, 1, 2000),
          share(2, 3, 2000),
        ],
        settlements: const [],
      );

      final pairs = result.suggestions.map(
        (s) => (s.fromMemberId, s.toMemberId),
      );
      expect(pairs.toSet(), hasLength(result.suggestions.length));
      expect(result.totalOutstanding, 2000);
    });

    test('respects already-paid settlement amounts', () {
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 5000)],
        shares: [share(1, 2, 5000)],
        settlements: [settlement(1, 2, 1, 5000, paidMinor: 3000)],
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.single.minor, 2000);
    });

    test('keeps net positions balanced and self-consistent', () {
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 3000), expense(2, 2, 2000)],
        shares: [
          share(1, 1, 1000),
          share(1, 2, 1000),
          share(1, 3, 1000),
          share(2, 1, 1000),
          share(2, 3, 1000),
        ],
        settlements: const [],
      );

      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);
      expect(
        result.totalOutstanding,
        result.remainingNets.values
            .where((v) => v > 0)
            .fold(0, (s, v) => s + v),
      );
    });

    test('external portion is excluded from settlement nets', () {
      // Member 1 pays 730.90 with 365.50 external, own share 365.40.
      // Only the group 365.40 can ever create a debt.
      final result = SettlementCalculator.calculate(
        expenses: [expense(1, 1, 73090, externalAmountMinor: 36550)],
        shares: [share(1, 1, 36540)],
        settlements: const [],
      );

      expect(result.suggestions, isEmpty);
      expect(result.remainingNets[1], 0);
    });
  });
}
