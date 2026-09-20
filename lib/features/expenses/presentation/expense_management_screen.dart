import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/trip_shell.dart';
import '../../../core/calculations/money.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../trips/data/trip_views.dart';
import '../domain/expense.dart';
import '../domain/expense_scope.dart';

/// Primary expense view for a trip, replacing [ExpenseListScreen].
///
/// Displays a summary header, search, category filters and a scrollable list
/// of expense cards. Each card navigates to the expense detail screen.
class ExpenseManagementScreen extends ConsumerStatefulWidget {
  const ExpenseManagementScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<ExpenseManagementScreen> createState() =>
      _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState
    extends ConsumerState<ExpenseManagementScreen> {
  String _searchQuery = '';
  String? _selectedCategory;

  static const _categories = [
    'Transport',
    'Food',
    'Accommodation',
    'Activities',
    'Shopping',
    'Misc',
  ];

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(tripViewProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Add expense',
            icon: const Icon(Icons.add),
            onPressed: () => context.push(AppRoutes.addExpense(widget.tripId)),
          ),
        ],
      ),
      body: TripShell(
        tripId: widget.tripId,
        selectedIndex: 1,
        child: SafeArea(
          bottom: false,
          child: AsyncValueView<TripView?>(
            value: view,
            onRetry: () => ref.invalidate(tripViewProvider(widget.tripId)),
            isEmpty: (value) => value == null || value.expenses.isEmpty,
            empty: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses yet',
              message: 'Record the first expense to start the split.',
              actionLabel: 'Add first expense',
              onAction: () => context.push(AppRoutes.addExpense(widget.tripId)),
            ),
            builder: (tripView) {
              if (tripView == null) {
                return const SizedBox.shrink();
              }
              final theme = Theme.of(context);
              final expenses = tripView.expenses;

              final totalAmount = expenses.fold<int>(
                0,
                (sum, e) => sum + e.expense.amountMinor,
              );
              final filtered = expenses.where((item) {
                final matchesSearch =
                    _searchQuery.isEmpty ||
                    item.expense.description.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    );
                final matchesCategory =
                    _selectedCategory == null ||
                    item.expense.category == _selectedCategory;
                return matchesSearch && matchesCategory;
              }).toList();

              final filteredExpenseIds = filtered
                  .map((e) => e.expense.id)
                  .toSet();
              final totalPaid = tripView.payments
                  .where((p) => filteredExpenseIds.contains(p.expenseId))
                  .fold<int>(0, (sum, p) => sum + p.amountMinor);
              final totalShares = filtered
                  .expand((e) => e.shares)
                  .fold<int>(0, (sum, s) => sum + s.shareMinor);
              final totalExternal = filtered
                  .where((e) => e.expense.externalAmountMinor > 0)
                  .fold<int>(
                    0,
                    (sum, e) => sum + e.expense.externalAmountMinor,
                  );

              return CustomScrollView(
                slivers: [
                  // ── Summary header ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: _SummaryHeader(
                        expenseCount: expenses.length,
                        totalAmount: totalAmount,
                        totalPaid: totalPaid,
                        totalShares: totalShares,
                        totalExternal: totalExternal,
                      ),
                    ),
                  ),

                  // ── Search bar ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search expenses...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Category filter chips ───────────────────────────────
                  if (expenses.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.xs,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.xxs,
                              ),
                              child: FilterChip(
                                label: const Text('All'),
                                selected: _selectedCategory == null,
                                onSelected: (_) =>
                                    setState(() => _selectedCategory = null),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            for (final cat in _categories)
                              if (expenses.any(
                                (e) => e.expense.category == cat,
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.xxs,
                                  ),
                                  child: FilterChip(
                                    label: Text(cat),
                                    selected: _selectedCategory == cat,
                                    onSelected: (_) => setState(
                                      () => _selectedCategory =
                                          _selectedCategory == cat ? null : cat,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),

                  // ── Filtered count ──────────────────────────────────────
                  if (filtered.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${filtered.length} expense${filtered.length == 1 ? '' : 's'}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Total: ${MoneyCalculator.format(filtered.fold<int>(0, (sum, e) => sum + e.expense.amountMinor))}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Expense list ────────────────────────────────────────
                  if (filtered.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.only(top: 64),
                        child: Center(child: Text('No matching expenses.')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final expense = item.expense;
                          final payer = tripView.memberById(
                            expense.payerMemberId,
                          );
                          final splitLabel = expense.scope.label;
                          return _ExpenseCard(
                            expense: expense,
                            payerName: payer.name,
                            participantCount: item.shares.length,
                            splitLabel: splitLabel,
                            onTap: () => context.push(
                              AppRoutes.expense(widget.tripId, expense.id),
                            ),
                          );
                        },
                      ),
                    ),

                  // ── Bottom spacing ─────────────────────────────────────
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Summary header card ─────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.expenseCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalShares,
    required this.totalExternal,
  });

  final int expenseCount;
  final int totalAmount;
  final int totalPaid;
  final int totalShares;
  final int totalExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$expenseCount expense${expenseCount == 1 ? '' : 's'}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _SummaryStat(
                  label: 'Total',
                  amount: totalAmount,
                  color: colorScheme.onSurface,
                ),
                _SummaryStat(
                  label: 'Paid',
                  amount: totalPaid,
                  color: colorScheme.primary,
                ),
                _SummaryStat(
                  label: 'External',
                  amount: totalExternal,
                  color: colorScheme.tertiary,
                ),
                _SummaryStat(
                  label: 'Shares',
                  amount: totalShares,
                  color: colorScheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.statLabel),
        const SizedBox(height: AppSpacing.xxs),
        MoneyText(
          amount,
          style: theme.textTheme.statValue.copyWith(color: color),
        ),
      ],
    );
  }
}

// ─── Expense card ────────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.payerName,
    required this.participantCount,
    required this.splitLabel,
    required this.onTap,
  });

  final Expense expense;
  final String payerName;
  final int participantCount;
  final String splitLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              MemberAvatar(expense.description),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Paid by $payerName · $participantCount ${participantCount == 1 ? 'way' : 'ways'}',
                      style: theme.textTheme.captionMuted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    expense.amountMinor,
                    style: theme.textTheme.titleBold,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      splitLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
