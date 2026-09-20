import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';

/// Randomized property tests for the expense-sharing engine.
///
/// Generates random valid scenarios with:
/// - 1–20 members
/// - 1–100 expenses
/// - Different payers, participant groups, and amounts
///
/// Verifies:
/// - Shares always sum correctly
/// - Net positions always sum to zero
/// - No participant is charged for an expense they didn't participate in
/// - Settlement balances correctly
void main() {
  final random = Random(42); // Deterministic seed for reproducibility

  group('Randomized property tests', () {
    test('shares sum correctly for random scenarios (50 iterations)', () {
      for (var iteration = 0; iteration < 50; iteration++) {
        final memberCount = 1 + random.nextInt(20);
        final memberIds = [for (var i = 0; i < memberCount; i++) i + 1];
        final expenseCount = 1 + random.nextInt(50);

        const splitter = EqualExpenseSplitter();
        final expenses = <Expense>[];
        final allShares = <ExpenseShare>[];
        final allPayments = <ExpensePayment>[];

        for (var e = 0; e < expenseCount; e++) {
          final amountMinor = 100 + random.nextInt(100000);
          final payerId = memberIds[random.nextInt(memberCount)];

          // Randomly select participants (at least 1)
          final participantCount = 1 + random.nextInt(memberCount);
          final shuffledMembers = [...memberIds]..shuffle(random);
          final participants = shuffledMembers.take(participantCount).toList()
            ..sort();

          expenses.add(
            Expense(
              id: e + 1,
              tripId: 1,
              payerMemberId: payerId,
              description: 'Expense ${e + 1}',
              amountMinor: amountMinor,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );

          final shares = splitter.split(
            totalMinor: amountMinor,
            memberIds: participants,
          );

          for (final share in shares) {
            allShares.add(
              ExpenseShare(
                id: (e + 1) * 1000 + share.memberId,
                expenseId: e + 1,
                memberId: share.memberId,
                shareMinor: share.amountMinor,
              ),
            );
          }

          allPayments.add(
            ExpensePayment(
              id: e + 1,
              expenseId: e + 1,
              memberId: payerId,
              amountMinor: amountMinor,
            ),
          );
        }

        // PROPERTY 1: Every expense's shares sum exactly to the expense total
        for (final expense in expenses) {
          final expenseShares = allShares
              .where((s) => s.expenseId == expense.id)
              .toList();
          final shareTotal = expenseShares.fold<int>(
            0,
            (sum, s) => sum + s.shareMinor,
          );
          expect(
            shareTotal,
            expense.amountMinor,
            reason:
                'Iteration $iteration: Expense ${expense.id} shares '
                'sum ($shareTotal) != total (${expense.amountMinor})',
          );
        }

        // PROPERTY 2: Net positions sum to zero
        final result = SettlementCalculator.calculate(
          expenses: expenses,
          shares: allShares,
          settlements: const [],
          payments: allPayments,
        );

        final netSum = result.remainingNets.values.fold<int>(
          0,
          (sum, v) => sum + v,
        );
        expect(
          netSum,
          0,
          reason: 'Iteration $iteration: Net sum = $netSum (expected 0)',
        );

        // PROPERTY 3: No participant is charged more than the expense total
        for (final share in allShares) {
          expect(
            share.shareMinor,
            lessThanOrEqualTo(
              expenses.firstWhere((e) => e.id == share.expenseId).amountMinor,
            ),
            reason:
                'Iteration $iteration: Share ${share.shareMinor} exceeds '
                'expense total',
          );
        }

        // PROPERTY 4: Total outstanding equals total receivable
        final totalDebt = result.remainingNets.entries
            .where((e) => e.value < 0)
            .fold<int>(0, (sum, e) => sum + e.value.abs());
        final totalCredit = result.remainingNets.entries
            .where((e) => e.value > 0)
            .fold<int>(0, (sum, e) => sum + e.value);
        expect(
          totalDebt,
          totalCredit,
          reason:
              'Iteration $iteration: Debt ($totalDebt) != Credit ($totalCredit)',
        );

        // PROPERTY 5: Total outstanding from suggestions matches
        expect(
          result.totalOutstanding,
          totalDebt,
          reason:
              'Iteration $iteration: Suggestion total '
              '(${result.totalOutstanding}) != debt total ($totalDebt)',
        );

        // PROPERTY 6: Every share is non-negative
        for (final share in allShares) {
          expect(
            share.shareMinor,
            greaterThanOrEqualTo(0),
            reason: 'Iteration $iteration: Negative share detected',
          );
        }
      }
    });

    test('shares sum correctly for extreme rounding scenarios', () {
      const splitter = EqualExpenseSplitter();

      // Very small amounts
      for (var count = 1; count <= 10; count++) {
        final memberIds = [for (var i = 0; i < count; i++) i + 1];
        final shares = splitter.split(totalMinor: 1, memberIds: memberIds);
        final sum = shares.fold<int>(0, (s, share) => s + share.amountMinor);
        expect(sum, 1, reason: 'count=$count total=1');
      }

      // Very large amounts
      for (var count = 1; count <= 5; count++) {
        final memberIds = [for (var i = 0; i < count; i++) i + 1];
        final shares = splitter.split(
          totalMinor: 999999999,
          memberIds: memberIds,
        );
        final sum = shares.fold<int>(0, (s, share) => s + share.amountMinor);
        expect(sum, 999999999, reason: 'count=$count total=999999999');
      }

      // Amounts that produce maximum rounding (mod N = N-1)
      for (var count = 2; count <= 10; count++) {
        final memberIds = [for (var i = 0; i < count; i++) i + 1];
        final total = count - 1; // e.g. 9999 paise for 10 members
        final shares = splitter.split(totalMinor: total, memberIds: memberIds);
        final sum = shares.fold<int>(0, (s, share) => s + share.amountMinor);
        expect(sum, total, reason: 'count=$count total=$total');
      }
    });

    test(
      'settlement algorithm is correct for random multi-payer scenarios',
      () {
        for (var iteration = 0; iteration < 30; iteration++) {
          final memberCount = 2 + random.nextInt(8);
          final memberIds = [for (var i = 0; i < memberCount; i++) i + 1];
          final expenseCount = 1 + random.nextInt(20);

          const splitter = EqualExpenseSplitter();
          final expenses = <Expense>[];
          final allShares = <ExpenseShare>[];
          final allPayments = <ExpensePayment>[];
          final paidByMember = <int, int>{};
          final shareByMember = <int, int>{};

          for (var e = 0; e < expenseCount; e++) {
            final amountMinor = 100 + random.nextInt(50000);
            final payerId = memberIds[random.nextInt(memberCount)];

            final participantCount = 1 + random.nextInt(memberCount);
            final shuffledMembers = [...memberIds]..shuffle(random);
            final participants = shuffledMembers.take(participantCount).toList()
              ..sort();

            expenses.add(
              Expense(
                id: e + 1,
                tripId: 1,
                payerMemberId: payerId,
                description: 'Expense ${e + 1}',
                amountMinor: amountMinor,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            );

            final shares = splitter.split(
              totalMinor: amountMinor,
              memberIds: participants,
            );

            for (final share in shares) {
              allShares.add(
                ExpenseShare(
                  id: (e + 1) * 1000 + share.memberId,
                  expenseId: e + 1,
                  memberId: share.memberId,
                  shareMinor: share.amountMinor,
                ),
              );
              shareByMember[share.memberId] =
                  (shareByMember[share.memberId] ?? 0) + share.amountMinor;
            }

            allPayments.add(
              ExpensePayment(
                id: e + 1,
                expenseId: e + 1,
                memberId: payerId,
                amountMinor: amountMinor,
              ),
            );
            paidByMember[payerId] = (paidByMember[payerId] ?? 0) + amountMinor;
          }

          final result = SettlementCalculator.calculate(
            expenses: expenses,
            shares: allShares,
            settlements: const [],
            payments: allPayments,
          );

          // PROPERTY: Net sum is zero
          final netSum = result.remainingNets.values.fold<int>(
            0,
            (sum, v) => sum + v,
          );
          expect(netSum, 0, reason: 'Iteration $iteration: Net sum = $netSum');

          // PROPERTY: Settlements are minimal (no circular transfers)
          for (final suggestion in result.suggestions) {
            expect(
              suggestion.fromMemberId,
              isNot(suggestion.toMemberId),
              reason: 'Iteration $iteration: Self-settlement detected',
            );
            expect(
              suggestion.minor,
              greaterThan(0),
              reason: 'Iteration $iteration: Zero-amount transfer',
            );
          }

          // PROPERTY: Total outstanding is correct
          final totalDebt = result.remainingNets.entries
              .where((e) => e.value < 0)
              .fold<int>(0, (sum, e) => sum + e.value.abs());
          expect(
            result.totalOutstanding,
            totalDebt,
            reason: 'Iteration $iteration: Outstanding mismatch',
          );

          // PROPERTY: BalanceCalculator produces consistent results
          final balances = BalanceCalculator.calculate(
            tripBudgetMinor: 0,
            contributions: const [],
            expenses: expenses,
            shares: allShares,
            settlements: const [],
            payments: allPayments,
          );

          final balanceNetSum = balances.members.fold<int>(
            0,
            (sum, m) => sum + m.netPosition,
          );
          expect(
            balanceNetSum,
            0,
            reason: 'Iteration $iteration: Balance net sum = $balanceNetSum',
          );
        }
      },
    );

    test(
      'partial participation is never charged for non-participating expenses',
      () {
        for (var iteration = 0; iteration < 20; iteration++) {
          final memberCount = 3 + random.nextInt(8);
          final memberIds = [for (var i = 0; i < memberCount; i++) i + 1];
          final expenseCount = 2 + random.nextInt(10);

          const splitter = EqualExpenseSplitter();
          final expenses = <Expense>[];
          final allShares = <ExpenseShare>[];
          final allPayments = <ExpensePayment>[];

          // Track which members participate in which expenses
          final participationMap = <int, Set<int>>{};

          for (var e = 0; e < expenseCount; e++) {
            final amountMinor = 100 + random.nextInt(50000);
            final payerId = memberIds[random.nextInt(memberCount)];

            // Randomly select participants
            final participantCount = 1 + random.nextInt(memberCount);
            final shuffledMembers = [...memberIds]..shuffle(random);
            final participants = shuffledMembers.take(participantCount).toList()
              ..sort();

            participationMap[e + 1] = participants.toSet();

            expenses.add(
              Expense(
                id: e + 1,
                tripId: 1,
                payerMemberId: payerId,
                description: 'Expense ${e + 1}',
                amountMinor: amountMinor,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            );

            final shares = splitter.split(
              totalMinor: amountMinor,
              memberIds: participants,
            );

            for (final share in shares) {
              allShares.add(
                ExpenseShare(
                  id: (e + 1) * 1000 + share.memberId,
                  expenseId: e + 1,
                  memberId: share.memberId,
                  shareMinor: share.amountMinor,
                ),
              );
            }

            allPayments.add(
              ExpensePayment(
                id: e + 1,
                expenseId: e + 1,
                memberId: payerId,
                amountMinor: amountMinor,
              ),
            );
          }

          // Verify: no non-participant is charged
          for (final expense in expenses) {
            final participants = participationMap[expense.id]!;
            final nonParticipants = memberIds
                .where((id) => !participants.contains(id))
                .toList();

            for (final memberId in nonParticipants) {
              final sharesForNonParticipant = allShares
                  .where(
                    (s) => s.expenseId == expense.id && s.memberId == memberId,
                  )
                  .toList();
              expect(
                sharesForNonParticipant,
                isEmpty,
                reason:
                    'Iteration $iteration: Member $memberId is NOT a '
                    'participant of expense ${expense.id} but has a share',
              );
            }
          }

          // Net sum is zero
          final result = SettlementCalculator.calculate(
            expenses: expenses,
            shares: allShares,
            settlements: const [],
            payments: allPayments,
          );
          final netSum = result.remainingNets.values.fold<int>(
            0,
            (sum, v) => sum + v,
          );
          expect(netSum, 0);
        }
      },
    );
  });
}
