import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_financial_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/balances.dart';
import '../../../core/calculations/money.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../trips/data/trip_views.dart';

/// Balances screen shown at `/trip/:tripId/balances`.
///
/// Presents the per-member financial breakdown: contribution, actual paid,
/// expense share, cash remaining and the net position (Owes / Receives), plus
/// the group budget summary.
class BalancesScreen extends ConsumerWidget {
  const BalancesScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Balances')),
      body: SafeArea(
        bottom: false,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const SizedBox.shrink(),
          builder: (tripView) {
            if (tripView == null) {
              return const SizedBox.shrink();
            }
            final balances = tripView.balances;
            final financial = context.financial;
            final theme = Theme.of(context);
            final fullySettled = balances.outstandingMinor == 0;
            final heroBackground = fullySettled
                ? financial.receivesContainer
                : financial.owesContainer;
            final heroForeground = fullySettled
                ? financial.onReceivesContainer
                : financial.onOwesContainer;

            return RefreshIndicator(
              onRefresh: () {
                ref.invalidate(tripViewProvider(tripId));
                return ref.read(tripViewProvider(tripId).future);
              },
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    color: heroBackground,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Icon(
                            fullySettled
                                ? Icons.check_circle_outline
                                : Icons.savings_outlined,
                            color: heroForeground,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullySettled
                                      ? 'Group is balanced'
                                      : 'Outstanding to settle',
                                  style: theme.textTheme.titleBold.copyWith(
                                    color: heroForeground,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fullySettled
                                      ? 'No money needs to change hands.'
                                      : 'Settle up before wrapping up.',
                                  style: theme.textTheme.captionMuted.copyWith(
                                    color: heroForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!fullySettled)
                            MoneyText(
                              balances.outstandingMinor,
                              style: theme.textTheme.moneyStrong.copyWith(
                                color: heroForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader('Group summary'),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _StatBox(
                                  label: 'Contributed',
                                  minor: balances.totalContributions,
                                ),
                              ),
                              Expanded(
                                child: _StatBox(
                                  label: 'Spent',
                                  minor: balances.paidMinor,
                                ),
                              ),
                              Expanded(
                                child: _StatBox(
                                  label: 'Budget left',
                                  minor: balances.remainingBudgetMinor,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _SummaryRow(
                            label: 'Cash remaining in the pool',
                            minor: balances.totalCashRemaining,
                          ),
                          _SummaryRow(
                            label: 'Total outstanding',
                            minor: balances.outstandingMinor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SectionHeader('Per member'),
                  for (final member in tripView.members) ...[
                    _MemberBalanceCard(
                      memberId: member.id,
                      name: member.name,
                      tripView: tripView,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.statLabel),
        const SizedBox(height: 4),
        MoneyText(minor, style: theme.textTheme.statValue),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          MoneyText(minor, style: theme.textTheme.statValue),
        ],
      ),
    );
  }
}

class _MemberBalanceCard extends StatelessWidget {
  const _MemberBalanceCard({
    required this.memberId,
    required this.name,
    required this.tripView,
  });

  final int memberId;
  final String name;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balances = tripView.balances.members;
    final row = balances.firstWhere(
      (b) => b.memberId == memberId,
      orElse: () => MemberBalance(
        memberId: memberId,
        contribution: 0,
        actualPaid: 0,
        expenseShare: 0,
        netPosition: 0,
        cashRemaining: 0,
        effectiveNetPosition: 0,
      ),
    );

    final tone = row.effectiveNetPosition > 0
        ? StatusTone.success
        : row.effectiveNetPosition < 0
        ? StatusTone.warning
        : StatusTone.neutral;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.title),
                      const SizedBox(height: 2),
                      MoneyText(
                        row.contribution,
                        style: theme.textTheme.bodyMuted,
                      ),
                    ],
                  ),
                ),
                StatusChip(row.netLabel, tone: tone),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _BalanceStatRow(label: 'Actual paid', minor: row.actualPaid),
            _BalanceStatRow(label: 'Expense share', minor: row.expenseShare),
            _BalanceStatRow(label: 'Cash remaining', minor: row.cashRemaining),
            const SizedBox(height: 4),
            _SettlementBreakdown(memberId: memberId, tripView: tripView),
            _ExpenseBreakdown(memberId: memberId, tripView: tripView),
          ],
        ),
      ),
    );
  }
}

class _BalanceStatRow extends StatelessWidget {
  const _BalanceStatRow({required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMuted)),
          MoneyText(minor, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SettlementBreakdown extends StatelessWidget {
  const _SettlementBreakdown({required this.memberId, required this.tripView});

  final int memberId;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = tripView.settlementPlan;

    // Find all transfers involving this member
    final receivesFrom = <_TransferEntry>[];
    final paysTo = <_TransferEntry>[];

    for (final suggestion in plan.suggestions) {
      if (suggestion.toMemberId == memberId && suggestion.minor > 0) {
        final fromName = tripView.memberById(suggestion.fromMemberId).name;
        receivesFrom.add(
          _TransferEntry(name: fromName, minor: suggestion.minor),
        );
      }
      if (suggestion.fromMemberId == memberId && suggestion.minor > 0) {
        final toName = tripView.memberById(suggestion.toMemberId).name;
        paysTo.add(_TransferEntry(name: toName, minor: suggestion.minor));
      }
    }

    if (receivesFrom.isEmpty && paysTo.isEmpty) {
      return const SizedBox.shrink();
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.xl),
        title: Text(
          'Settlement transfers',
          style: theme.textTheme.captionMuted,
        ),
        children: [
          if (paysTo.isNotEmpty) ...[
            for (final entry in paysTo)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pays ${entry.name}',
                        style: theme.textTheme.bodyMuted,
                      ),
                    ),
                    MoneyText(entry.minor, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
          if (receivesFrom.isNotEmpty) ...[
            for (final entry in receivesFrom)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Receives from ${entry.name}',
                        style: theme.textTheme.bodyMuted,
                      ),
                    ),
                    MoneyText(entry.minor, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferEntry {
  const _TransferEntry({required this.name, required this.minor});
  final String name;
  final int minor;
}

class _ExpenseBreakdown extends StatelessWidget {
  const _ExpenseBreakdown({required this.memberId, required this.tripView});

  final int memberId;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paymentsByExpense = PaymentAllocator.byExpense(tripView.payments);
    final effects = <MemberExpenseEffect>[];
    for (final item in tripView.expenses) {
      effects.addAll(
        PaymentAllocator.effectsPerExpense(
          expense: item.expense,
          shares: item.shares,
          paymentsByExpense: paymentsByExpense,
        ),
      );
    }
    final mine = effects.where((effect) => effect.memberId == memberId).toList()
      ..sort((a, b) => a.expenseId.compareTo(b.expenseId));
    if (mine.isEmpty) {
      return const SizedBox.shrink();
    }
    String expenseName(int expenseId) {
      for (final item in tripView.expenses) {
        if (item.expense.id == expenseId) {
          return item.expense.description;
        }
      }
      return 'Expense #$expenseId';
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.xl),
        title: Text(
          'Per-expense breakdown',
          style: theme.textTheme.captionMuted,
        ),
        children: [
          for (final effect in mine)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expenseName(effect.expenseId),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          effect.netMinor == 0
                              ? 'Paid their share'
                              : effect.netMinor > 0
                              ? 'Paid ${MoneyCalculator.format(effect.netMinor)} more than their share'
                              : 'Owes ${MoneyCalculator.format(-effect.netMinor)} to the group',
                          style: theme.textTheme.captionMuted,
                        ),
                      ),
                      MoneyText(
                        effect.paidMinor,
                        style: theme.textTheme.bodyMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
