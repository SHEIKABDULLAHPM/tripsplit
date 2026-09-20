import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../injection/database_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_scope.dart';
import '../../expenses/domain/expense_share.dart';
import '../../notes/domain/note.dart';
import '../../trips/data/trip_views.dart';

/// Expense details screen shown at `/trip/:tripId/expenses/:expenseId`.
///
/// Shows all the information about an expense including the per-participant
/// shares, travel segment, scope, non-participating members, and offers
/// edit and delete actions.
class ExpenseDetailsScreen extends ConsumerWidget {
  const ExpenseDetailsScreen({
    super.key,
    required this.tripId,
    required this.expenseId,
  });

  final int tripId;
  final int expenseId;

  Future<void> _showQuickNote(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'e.g. Receipt #12345',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      final expense = ref
          .read(tripViewProvider(tripId))
          .value
          ?.expenses
          .where((e) => e.expense.id == expenseId)
          .firstOrNull;
      if (expense != null) {
        try {
          await ref
              .read(noteRepositoryProvider)
              .save(
                Note(
                  id: 0,
                  tripId: tripId,
                  title: 'Note: ${expense.expense.description}',
                  body: result,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Note saved.')));
          }
        } on AppException catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Delete expense?',
      message: 'This also removes every member share and updates the balances.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(expenseRepositoryProvider)
          .deleteExpense(tripId: tripId, expenseId: expenseId);
      if (context.mounted) {
        context.go(AppRoutes.expenses(tripId));
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(tripViewProvider(tripId));
    final journey = ref.watch(journeyViewProvider(tripId));
    final teams = ref.watch(teamsForTripProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          IconButton(
            tooltip: 'Quick note',
            onPressed: () => _showQuickNote(context, ref),
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () =>
                context.push(AppRoutes.editExpense(tripId, expenseId)),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Expense not found',
            message: 'This expense may have been deleted.',
          ),
          builder: (tripView) {
            if (tripView == null) {
              return const SizedBox.shrink();
            }
            final items = tripView.expenses.where(
              (item) => item.expense.id == expenseId,
            );
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Expense not found',
                message: 'This expense may have been deleted.',
              );
            }
            final item = items.first;
            final expense = item.expense;
            final payer = tripView.memberById(expense.payerMemberId);
            final hasExternal = expense.externalAmountMinor > 0;

            // Payment data for this expense.
            final paymentsForExpense = tripView.payments
                .where((p) => p.expenseId == expense.id)
                .toList();
            final totalPaid = paymentsForExpense.fold<int>(
              0,
              (sum, p) => sum + p.amountMinor,
            );
            final isFullyPaid = totalPaid >= expense.amountMinor;

            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MemberAvatar(expense.description, radius: 14),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                expense.description,
                                style: theme.textTheme.screenTitle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        MoneyText(
                          expense.amountMinor,
                          style: theme.textTheme.moneyHero,
                        ),
                        const SizedBox(height: 4),
                        if (hasExternal)
                          Text(
                            'External portion held by ${payer.name}',
                            style: theme.textTheme.captionMuted,
                          ),
                        const SizedBox(height: 16),
                        _InfoRow(label: 'Paid by', value: payer.name),
                        if (hasExternal) ...[
                          const SizedBox(height: 2),
                          _InfoRow(
                            label: 'External (not shared)',
                            value: MoneyCalculator.format(
                              expense.externalAmountMinor,
                            ),
                            emphasize: true,
                          ),
                          _InfoRow(
                            label: 'Group share',
                            value: MoneyCalculator.format(
                              expense.amountMinor - expense.externalAmountMinor,
                            ),
                          ),
                        ],
                        _InfoRow(
                          label: 'Date',
                          value: DateFormats.date(
                            expense.spentAt ?? expense.createdAt,
                          ),
                        ),
                        if (expense.category != null)
                          _InfoRow(label: 'Category', value: expense.category!),
                        if (expense.segmentId != null) ...[
                          const SizedBox(height: 2),
                          _InfoRow(
                            label: 'Travel segment',
                            value: _segmentLabel(
                              journey.value,
                              expense.segmentId!,
                            ),
                          ),
                        ],
                        // Payment status
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: isFullyPaid
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withAlpha(80)
                                : Theme.of(context)
                                    .colorScheme
                                    .errorContainer
                                    .withAlpha(80),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isFullyPaid
                                        ? Icons.check_circle_outline
                                        : Icons.pending_outlined,
                                    size: 16,
                                    color: isFullyPaid
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .error,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isFullyPaid
                                        ? 'Fully paid'
                                        : 'Remaining: ${MoneyCalculator.format(expense.amountMinor - totalPaid)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: isFullyPaid
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Paid: ${MoneyCalculator.format(totalPaid)} of ${MoneyCalculator.format(expense.amountMinor)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .captionMuted,
                              ),
                            ],
                          ),
                        ),
                        _InfoRow(
                          label: 'Scope',
                          value: _scopeLabel(expense.scope),
                        ),
                        if (expense.teamIds.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          _InfoRow(
                            label: 'Teams',
                            value: [
                              for (final teamId in expense.teamIds)
                                teams.value
                                        ?.where((t) => t.id == teamId)
                                        .map((t) => t.name)
                                        .firstOrNull ??
                                    'Team $teamId',
                            ].join(', '),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // ── Who paid ──
                if (paymentsForExpense.isNotEmpty) ...[
                  SectionHeader(
                    'Who paid',
                    trailing: Text(
                      '${paymentsForExpense.length} payer${paymentsForExpense.length == 1 ? '' : 's'}',
                      style: theme.textTheme.captionMuted,
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final payment in paymentsForExpense)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: 2,
                            ),
                            leading: MemberAvatar(
                              tripView
                                  .memberById(payment.memberId)
                                  .name,
                              radius: 11,
                            ),
                            title: Text(
                              tripView
                                  .memberById(payment.memberId)
                                  .name,
                            ),
                            trailing: MoneyText(
                              payment.amountMinor,
                              style: theme.textTheme.titleBold,
                            ),
                          ),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Total paid',
                                style: theme.textTheme.bodyMuted,
                              ),
                              const Spacer(),
                              MoneyText(
                                totalPaid,
                                style: theme.textTheme.statValue,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SectionHeader(
                  'Split between',
                  trailing: Text(
                    '${item.shares.length} of ${tripView.members.length} members',
                    style: theme.textTheme.captionMuted,
                  ),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < item.shares.length; i++)
                        _MemberShareTile(
                          memberId: item.shares[i].memberId,
                          shareMinor: item.shares[i].shareMinor,
                          paidMinor: paymentsForExpense
                              .where((p) =>
                                  p.memberId == item.shares[i].memberId)
                              .fold<int>(
                                0,
                                (sum, p) => sum + p.amountMinor,
                              ),
                          tripView: tripView,
                        ),
                    ],
                  ),
                ),
                // Show non-participating members
                ..._nonParticipatingMembers(
                  expense: expense,
                  shares: item.shares,
                  tripView: tripView,
                  theme: theme,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _segmentLabel(JourneyView? journey, int segmentId) {
    if (journey == null) return 'Unknown segment';
    for (final segment in journey.segments) {
      if (segment.id == segmentId) {
        final start =
            journey.locationById(segment.startLocationId)?.name ?? '?';
        final end = journey.locationById(segment.endLocationId)?.name ?? '?';
        return '$start → $end';
      }
    }
    return 'Unknown segment';
  }

  static String _scopeLabel(ExpenseScope scope) => switch (scope) {
    ExpenseScope.individual => 'Individual',
    ExpenseScope.shared => 'Shared',
    ExpenseScope.team => 'Team',
    ExpenseScope.segment => 'Travel segment',
    ExpenseScope.custom => 'Custom',
  };

  static List<Widget> _nonParticipatingMembers({
    required Expense expense,
    required List<ExpenseShare> shares,
    required TripView tripView,
    required ThemeData theme,
  }) {
    final participantIds = shares.map((s) => s.memberId).toSet();
    final nonParticipants = tripView.members
        .where((m) => !participantIds.contains(m.id))
        .toList();
    if (nonParticipants.isEmpty) return const [];
    return [
      SectionHeader(
        'Not participating',
        trailing: Text(
          '${nonParticipants.length} member${nonParticipants.length == 1 ? '' : 's'}',
          style: theme.textTheme.captionMuted,
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final member in nonParticipants)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 2,
                ),
                leading: MemberAvatar(member.name, radius: 11),
                title: Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withAlpha(128),
                  ),
                ),
                trailing: Text(
                  'Not participating',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.captionMuted,
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

class _MemberShareTile extends StatelessWidget {
  const _MemberShareTile({
    required this.memberId,
    required this.shareMinor,
    required this.paidMinor,
    required this.tripView,
  });

  final int memberId;
  final int shareMinor;
  final int paidMinor;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = paidMinor - shareMinor;
    final memberName = tripView.memberById(memberId).name;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: MemberAvatar(memberName, radius: 11),
      title: Text(memberName),
      subtitle: paidMinor > 0
          ? Text(
              'Paid ${MoneyCalculator.format(paidMinor)} · Share ${MoneyCalculator.format(shareMinor)}',
              style: theme.textTheme.captionMuted,
            )
          : Text(
              'Share ${MoneyCalculator.format(shareMinor)}',
              style: theme.textTheme.captionMuted,
            ),
      trailing: Text(
        net >= 0
            ? '+${MoneyCalculator.format(net)}'
            : '-${MoneyCalculator.format(-net)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: net > 0
              ? theme.colorScheme.primary
              : net < 0
              ? theme.colorScheme.error
              : null,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMuted)),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasize
                  ? theme.textTheme.statValue
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
