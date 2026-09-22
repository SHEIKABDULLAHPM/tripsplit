import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

void main() {
  final now = DateTime(2026, 9, 12);

  Contribution contribution(int memberId, int amountMinor) => Contribution(
    id: memberId,
    tripId: 1,
    memberId: memberId,
    amountMinor: amountMinor,
    createdAt: now,
  );

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

  group('BalanceCalculator', () {
    test('computes contribution, actualPaid and expenseShare distinctly', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: [contribution(1, 30000), contribution(2, 20000)],
        expenses: [
          expense(1, 1, 10000), // paid by member 1
        ],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: const [],
      );

      expect(result.totalContributions, 50000);
      expect(result.totalExpenses, 10000);
      expect(result.remainingBudget, 90000);

      final member1 = result.members.firstWhere((m) => m.memberId == 1);
      final member2 = result.members.firstWhere((m) => m.memberId == 2);

      expect(member1.contribution, 30000);
      expect(member1.actualPaid, 10000);
      expect(member1.expenseShare, 5000);
      expect(member1.netPosition, 5000);
      expect(member1.amountToReceive, 5000);
      expect(member1.amountToPay, 0);

      expect(member2.actualPaid, 0);
      expect(member2.expenseShare, 5000);
      expect(member2.netPosition, -5000);
      expect(member2.amountToPay, 5000);
      expect(member2.amountToReceive, 0);
    });

    test('cash remaining uses paid settlements, not expense shares', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: [contribution(1, 50000), contribution(2, 50000)],
        expenses: [expense(1, 1, 20000)],
        shares: [share(1, 1, 10000), share(1, 2, 10000)],
        settlements: [settlement(1, 2, 1, 10000, paidMinor: 10000)],
      );

      // Member 2 sent 100.00 to member 1 as a settlement. Cash remaining is
      // the member's contribution minus its actual expense payments (zero,
      // because member 1 paid) minus settlements it sent.
      final member2 = result.members.firstWhere((m) => m.memberId == 2);
      expect(member2.contribution, 50000);
      expect(member2.actualPaid, 0);
      expect(member2.cashRemaining, 50000 - 10000);
      expect(member2.cashRemaining, 40000);
    });

    test('net position is zero and balanced when payments equal shares', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 50000,
        contributions: [contribution(1, 50000)],
        expenses: [expense(1, 1, 30000)],
        shares: [share(1, 1, 30000)],
        settlements: const [],
      );

      final member = result.members.single;
      expect(member.netPosition, 0);
      expect(member.netLabel, 'Balanced');
      expect(member.amountToPay, 0);
      expect(member.amountToReceive, 0);
    });

    test('exposes total outstanding across the group', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: [expense(1, 1, 5000)],
        shares: [share(1, 2, 5000)],
        settlements: const [],
      );

      expect(result.outstandingMinor, 5000);
    });

    test('external portion is excluded from group spend and net positions', () {
      // Member 1 pays 730.90 for a registration. 365.50 is external (not
      // shared) and 365.40 is their own share only — no group debt.
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: [contribution(1, 73090), contribution(2, 50000)],
        expenses: [expense(1, 1, 73090, externalAmountMinor: 36550)],
        shares: [share(1, 1, 36540)],
        settlements: const [],
      );

      // Budget only sees the 365.40 group share, not the full payment.
      expect(result.totalExpenses, 36540);
      expect(result.remainingBudget, 100000 - 36540);

      final member1 = result.members.firstWhere((m) => m.memberId == 1);
      // actualPaid is the full out-of-pocket amount.
      expect(member1.actualPaid, 73090);
      // expenseShare is just their group responsibility.
      expect(member1.expenseShare, 36540);
      // netPosition uses the group portion: groupOutlay(36540) - share(36540) = 0
      expect(member1.netPosition, 0);
      // cashRemaining: contribution(73090) - actualPaid(73090) = 0
      expect(member1.cashRemaining, 0);

      final member2 = result.members.firstWhere((m) => m.memberId == 2);
      expect(member2.netPosition, 0);
      expect(member2.cashRemaining, 50000);
    });

    test(
      'external multi-participant expense splits only the group portion',
      () {
        // 733.60 paid by member 1. External 100.00, group share 633.60
        // split equally between all 3 members.
        final result = BalanceCalculator.calculate(
          tripBudgetMinor: 100000,
          contributions: [contribution(1, 100000)],
          expenses: [expense(1, 1, 73360, externalAmountMinor: 10000)],
          shares: [share(1, 1, 21120), share(1, 2, 21120), share(1, 3, 21120)],
          settlements: const [],
        );

        expect(result.totalExpenses, 63360);

        final member1 = result.members.firstWhere((m) => m.memberId == 1);
        expect(member1.actualPaid, 73360);
        expect(member1.expenseShare, 21120);
        // groupOutlay (63360) - share (21120) = +42240
        expect(member1.netPosition, 42240);
        // cash: 100000 - 73360 = 26640
        expect(member1.cashRemaining, 26640);
      },
    );

    test('negative external portion is rejected', () {
      expect(
        () => BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: const [],
          expenses: [expense(1, 1, 1000, externalAmountMinor: -1)],
          shares: const [],
          settlements: const [],
        ),
        throwsArgumentError,
      );
    });

    test('external greater than amount is rejected', () {
      expect(
        () => BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: const [],
          expenses: [expense(1, 1, 100, externalAmountMinor: 100)],
          shares: const [],
          settlements: const [],
        ),
        throwsArgumentError,
      );
    });

    test(
      'effectiveNetPosition reduces by settlements the way the plan does',
      () {
        // Ana (member 1) fronts 730.80 for two equal 365.40 shares. Ben
        // (member 2) owes Ana 365.40. Ben pays 200.00, so 165.40 remains.
        final result = BalanceCalculator.calculate(
          tripBudgetMinor: 100000,
          contributions: [contribution(1, 73080), contribution(2, 10000)],
          expenses: [expense(1, 1, 73080)],
          shares: [share(1, 1, 36540), share(1, 2, 36540)],
          settlements: [
            settlement(1, 2, 1, 36540, paidMinor: 20000),
          ],
          postSettlementOutstanding: 16540,
        );

        final ana = result.members.firstWhere((m) => m.memberId == 1);
        final ben = result.members.firstWhere((m) => m.memberId == 2);

        expect(ana.netPosition, 36540);
        // Ana was paid 200.00, so she is owed 165.40, not 565.40.
        expect(ana.effectiveNetPosition, 16540);
        expect(ana.amountToReceive, 16540);
        expect(ana.amountToPay, 0);
        expect(ana.netLabel, 'Receives');

        expect(ben.netPosition, -36540);
        expect(ben.effectiveNetPosition, -16540);
        expect(ben.amountToPay, 16540);
        expect(ben.amountToReceive, 0);
        expect(ben.netLabel, 'Owes');

        expect(result.outstandingMinor, 16540);
      },
    );

    test('fully settled members show balanced, not inflated owes/receives', () {
      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 100000,
        contributions: [contribution(1, 50000), contribution(2, 10000)],
        expenses: [expense(1, 1, 10000)],
        shares: [share(1, 1, 5000), share(1, 2, 5000)],
        settlements: [settlement(1, 2, 1, 5000, paidMinor: 5000)],
        postSettlementOutstanding: 0,
      );

      for (final member in result.members) {
        expect(member.effectiveNetPosition, 0,
            reason: 'debt of member ${member.memberId} cleared after payment');
        expect(member.amountToPay, 0);
        expect(member.amountToReceive, 0);
        expect(member.netLabel, 'Balanced');
      }
    });
  });
}
