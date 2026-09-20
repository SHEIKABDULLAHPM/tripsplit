import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_financial_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/edit_trip_dialog.dart';
import '../../../app/widgets/trip_shell.dart';
import '../../../core/calculations/settlements.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../injection/database_providers.dart';
import '../../members/domain/member.dart';
import '../data/trip_views.dart';
import '../domain/trip.dart';

/// Trip home screen: overview with budget, balance, quick actions, journey & team summaries.
class TripDashboardScreen extends ConsumerWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));

    return Scaffold(
      body: TripShell(
        tripId: tripId,
        selectedIndex: 0,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const EmptyState(
            icon: Icons.luggage,
            title: 'Trip not found',
            message: 'This trip no longer exists.',
          ),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();
            final trip = tripView.trip;
            final balances = tripView.balances;
            final expenses = tripView.expenses;
            final members = tripView.members;

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  title: Text(trip.name),
                  actions: [
                    PopupMenuButton<String>(
                      tooltip: 'Trip options',
                      onSelected: (value) =>
                          _handleMenuAction(context, ref, value, trip),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit trip'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete trip'),
                        ),
                      ],
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ).copyWith(top: AppSpacing.lg, bottom: AppSpacing.xxl),
                  sliver: SliverList.list(
                    children: [
                      // Budget summary
                      _BudgetSummaryCard(
                        totalBudgetMinor: trip.totalBudgetMinor,
                        spentMinor: balances.paidMinor,
                        remainingMinor: balances.remainingBudgetMinor,
                        startDate: trip.startDate,
                        endDate: trip.endDate,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Balance hero
                      _BalanceHeroCard(
                        outstandingMinor: balances.outstandingMinor,
                        onOpenBalances: () =>
                            context.push(AppRoutes.balances(tripId)),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Primary contextual actions + section shortcuts
                      _QuickActionsCard(tripId: tripId),

                      // Member outstanding preview (live, post-settlement)
                      if (tripView.settlementPlan.remainingNets.values.any(
                        (value) => value != 0,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: _MemberOutstandingPreview(
                            plan: tripView.settlementPlan,
                            tripView: tripView,
                          ),
                        ),

                      // Recent expenses
                      SectionHeader(
                        'Recent expenses',
                        trailing: expenses.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () =>
                                    context.push(AppRoutes.expenses(tripId)),
                                child: const Text('See all'),
                              ),
                      ),
                      if (expenses.isEmpty)
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No expenses yet.',
                                  style: Theme.of(context).textTheme.bodyMuted,
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => context.push(
                                    AppRoutes.addExpense(tripId),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add the first expense'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < expenses.length && i < 3; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == 2 ? 0 : AppSpacing.sm,
                            ),
                            child: _RecentExpenseTile(
                              item: expenses[i],
                              members: members,
                              onTap: () => context.push(
                                AppRoutes.expense(
                                  tripId,
                                  expenses[i].expense.id,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Trip trip,
  ) {
    switch (action) {
      case 'edit':
        showDialog<void>(
          context: context,
          builder: (_) => EditTripDialog(trip: trip),
        );
      case 'delete':
        _confirmDelete(context, ref, trip);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Delete "${trip.name}"?',
      message:
          'This permanently removes the trip, all members, expenses, settlements, and journey data. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(tripRepositoryProvider).deleteById(trip.id);
      if (context.mounted) context.go(AppRoutes.home);
    } on AppException catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ── Budget Summary ──
class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.totalBudgetMinor,
    required this.spentMinor,
    required this.remainingMinor,
    this.startDate,
    this.endDate,
  });

  final int totalBudgetMinor;
  final int spentMinor;
  final int remainingMinor;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDates = startDate != null || endDate != null;
    final dateLabel = hasDates
        ? [
            if (startDate != null) 'Starts ${DateFormats.date(startDate!)}',
            if (endDate != null) 'Ends ${DateFormats.date(endDate!)}',
          ].join(' · ')
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group budget', style: theme.textTheme.statLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BudgetStat(label: 'Budget', minor: totalBudgetMinor),
                ),
                Expanded(
                  child: _BudgetStat(label: 'Spent', minor: spentMinor),
                ),
                Expanded(
                  child: _BudgetStat(label: 'Remaining', minor: remainingMinor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: totalBudgetMinor <= 0
                  ? 0
                  : (spentMinor / totalBudgetMinor).clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            if (dateLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(dateLabel, style: theme.textTheme.captionMuted),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetStat extends StatelessWidget {
  const _BudgetStat({required this.label, required this.minor});
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

// ── Balance Hero ──
class _BalanceHeroCard extends StatelessWidget {
  const _BalanceHeroCard({
    required this.outstandingMinor,
    required this.onOpenBalances,
  });
  final int outstandingMinor;
  final VoidCallback onOpenBalances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financial = context.financial;
    final outstanding = outstandingMinor > 0;
    final background = outstanding
        ? financial.owesContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = outstanding
        ? financial.onOwesContainer
        : theme.colorScheme.onSurface;

    return Card(
      margin: EdgeInsets.zero,
      color: background,
      child: InkWell(
        onTap: onOpenBalances,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                outstanding
                    ? Icons.savings_outlined
                    : Icons.check_circle_outline,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outstanding ? 'Outstanding balance' : 'Fully settled',
                      style: theme.textTheme.titleBold.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      outstanding
                          ? 'Settle up with suggested transfers.'
                          : 'All expenses are settled.',
                      style: theme.textTheme.bodyMuted.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (outstanding)
                      MoneyText(
                        outstandingMinor,
                        style: theme.textTheme.moneyStrong.copyWith(
                          color: foreground,
                        ),
                      )
                    else
                      Text(
                        'Balanced',
                        style: theme.textTheme.statValue.copyWith(
                          color: foreground,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick actions card ──
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick actions', style: theme.textTheme.statLabel),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.add_circle_outline,
                    label: 'Add expense',
                    onTap: () => context.push(AppRoutes.addExpense(tripId)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.payments_outlined,
                    label: 'Record payment',
                    onTap: () =>
                        context.push(AppRoutes.recordSettlement(tripId)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = AppSpacing.sm;
                const maxTileWidth = 120.0;
                final tileWidth = ((constraints.maxWidth - 2 * spacing) / 3)
                    .clamp(0.0, maxTileWidth)
                    .toDouble();
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    _QuickNavTile(
                      icon: Icons.people_outline,
                      label: 'People',
                      onTap: () => context.push(AppRoutes.people(tripId)),
                      width: tileWidth,
                    ),
                    _QuickNavTile(
                      icon: Icons.route_outlined,
                      label: 'Journey',
                      onTap: () => context.push(AppRoutes.journey(tripId)),
                      width: tileWidth,
                    ),
                    _QuickNavTile(
                      icon: Icons.groups_outlined,
                      label: 'Teams',
                      onTap: () => context.push(AppRoutes.teams(tripId)),
                      width: tileWidth,
                    ),
                    _QuickNavTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Balances',
                      onTap: () => context.push(AppRoutes.balances(tripId)),
                      width: tileWidth,
                    ),
                    _QuickNavTile(
                      icon: Icons.sticky_note_2_outlined,
                      label: 'Notes',
                      onTap: () => context.push(AppRoutes.notes(tripId)),
                      width: tileWidth,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNavTile extends StatelessWidget {
  const _QuickNavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.width,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Expense Tile ──
class _RecentExpenseTile extends StatelessWidget {
  const _RecentExpenseTile({
    required this.item,
    required this.members,
    required this.onTap,
  });
  final ExpenseWithShares item;
  final List<Member> members;
  final VoidCallback onTap;

  String _memberName(int memberId) {
    final member = members.firstWhere(
      (m) => m.id == memberId,
      orElse: () =>
          Member(id: memberId, tripId: 0, name: '?', createdAt: DateTime(2024)),
    );
    return member.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expense = item.expense;
    final payerName = _memberName(expense.payerMemberId);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: MemberAvatar(expense.description),
        title: Text(
          expense.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Paid by $payerName',
            style: theme.textTheme.captionMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: MoneyText(
          expense.amountMinor,
          style: theme.textTheme.statValue,
        ),
        onTap: onTap,
      ),
    );
  }
}

// ── Member Outstanding Preview ──
class _MemberOutstandingPreview extends StatelessWidget {
  const _MemberOutstandingPreview({required this.plan, required this.tripView});
  final SettlementResult plan;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Post-settlement positions from the live plan: the same source as the
    // outstanding hero and the settlements screen, so all three agree even
    // after expenses change or payments are recorded.
    final outstanding =
        plan.remainingNets.entries.where((entry) => entry.value != 0).toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Who owes whom', style: theme.textTheme.statLabel),
            const SizedBox(height: 8),
            for (final entry in outstanding)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    MemberAvatar(
                      tripView.memberById(entry.key).name,
                      radius: 12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tripView.memberById(entry.key).name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      entry.value > 0 ? 'Gets' : 'Owes',
                      style: entry.value > 0
                          ? theme.textTheme.positiveLabel
                          : theme.textTheme.warningLabel,
                    ),
                    const SizedBox(width: 8),
                    MoneyText(
                      entry.value.abs(),
                      style: theme.textTheme.statValue,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
