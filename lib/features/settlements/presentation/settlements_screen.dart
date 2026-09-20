import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_financial_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/trip_shell.dart';
import '../../../core/calculations/money.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../settlements/domain/settlement.dart';
import '../../trips/data/trip_views.dart';
import 'record_settlement_screen.dart' show RecordSettlementSelection;

/// Settlements screen: suggested transfers, payment history, contextual recording.
class SettlementsScreen extends ConsumerWidget {
  const SettlementsScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(tripViewProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settlements'),
        actions: [
          IconButton(
            tooltip: 'Record payment',
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => context.push(AppRoutes.recordSettlement(tripId)),
          ),
        ],
      ),
      body: TripShell(
        tripId: tripId,
        selectedIndex: 2,
        child: SafeArea(
          bottom: false,
          child: AsyncValueView<TripView?>(
            value: view,
            onRetry: () => ref.invalidate(tripViewProvider(tripId)),
            isEmpty: (value) => value == null,
            empty: const SizedBox.shrink(),
            builder: (tripView) {
              if (tripView == null) return const SizedBox.shrink();
              final plan = tripView.settlementPlan;
              final financial = context.financial;
              final hasOutstanding = plan.totalOutstanding > 0;
              final heroBg = hasOutstanding
                  ? financial.owesContainer
                  : financial.receivesContainer;
              final heroFg = hasOutstanding
                  ? financial.onOwesContainer
                  : financial.onReceivesContainer;

              return ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  // Hero card
                  Card(
                    margin: EdgeInsets.zero,
                    color: heroBg,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Icon(
                            hasOutstanding
                                ? Icons.swap_horiz
                                : Icons.check_circle_outline,
                            color: heroFg,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasOutstanding
                                      ? 'Outstanding to settle'
                                      : 'Group settled up',
                                  style: theme.textTheme.titleBold.copyWith(
                                    color: heroFg,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasOutstanding
                                      ? 'Suggested transfers below.'
                                      : 'All done — everyone is even.',
                                  style: theme.textTheme.captionMuted.copyWith(
                                    color: heroFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasOutstanding)
                            MoneyText(
                              plan.totalOutstanding,
                              style: theme.textTheme.moneyStrong.copyWith(
                                color: heroFg,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Suggested transfers
                  const SectionHeader('Suggested transfers'),
                  if (plan.suggestions.isEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Nothing to settle — the group is balanced.',
                          style: theme.textTheme.bodyMuted,
                        ),
                      ),
                    )
                  else
                    for (final suggestion in plan.suggestions) ...[
                      _SuggestionTile(
                        tripId: tripId,
                        fromId: suggestion.fromMemberId,
                        toId: suggestion.toMemberId,
                        fromName: tripView
                            .memberById(suggestion.fromMemberId)
                            .name,
                        toName: tripView.memberById(suggestion.toMemberId).name,
                        minor: suggestion.minor,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],

                  // History
                  const SectionHeader('History'),
                  if (tripView.settlements.isEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'No settlements recorded yet.',
                          style: theme.textTheme.bodyMuted,
                        ),
                      ),
                    )
                  else
                    for (final settlement in tripView.settlements) ...[
                      _HistoryTile(
                        settlement: settlement,
                        tripView: tripView,
                        tripId: tripId,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends ConsumerWidget {
  const _SuggestionTile({
    required this.tripId,
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.minor,
  });

  final int tripId;
  final int fromId;
  final int toId;
  final String fromName;
  final String toName;
  final int minor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            MemberAvatar(fromName, radius: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$fromName → $toName',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Suggested transfer',
                    style: theme.textTheme.captionMuted,
                  ),
                ],
              ),
            ),
            Flexible(child: MoneyText(minor, style: theme.textTheme.titleBold)),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Edit amount',
              onPressed: () => context.push(
                AppRoutes.recordSettlement(tripId),
                extra: RecordSettlementSelection(
                  fromMemberId: fromId,
                  toMemberId: toId,
                  amountMinor: minor,
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            FilledButton.tonal(
              onPressed: () => context.push(
                AppRoutes.recordSettlement(tripId),
                extra: RecordSettlementSelection(
                  fromMemberId: fromId,
                  toMemberId: toId,
                  amountMinor: minor,
                ),
              ),
              child: const Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.settlement,
    required this.tripView,
    required this.tripId,
  });
  final Settlement settlement;
  final TripView tripView;
  final int tripId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Figured from the live plan so history can never drift out of sync with
    // the outstanding hero or the suggested transfers when expenses change.
    final remaining = tripView.settlementRemainingBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );
    final paid = tripView.settlementPaidBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );
    final obligation = tripView.settlementObligationBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );
    final isFullyPaid = remaining <= 0;
    final subtitle = isFullyPaid
        ? 'Fully paid'
        : '${MoneyCalculator.format(paid)} of ${MoneyCalculator.format(obligation)} paid';

    final status = switch ((isFullyPaid, paid > 0)) {
      (true, _) => SettlementStatus.paid,
      (false, true) => SettlementStatus.partial,
      (false, false) => SettlementStatus.outstanding,
    };
    final tone = switch (status) {
      SettlementStatus.paid => StatusTone.success,
      SettlementStatus.partial => StatusTone.warning,
      SettlementStatus.outstanding => StatusTone.neutral,
    };
    final label = switch (status) {
      SettlementStatus.paid => 'Paid',
      SettlementStatus.partial => 'Partial',
      SettlementStatus.outstanding => 'Outstanding',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            context.push(AppRoutes.settlementDetail(tripId, settlement.id)),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              MemberAvatar(
                tripView.memberById(settlement.fromMemberId).name,
                radius: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tripView.memberById(settlement.fromMemberId).name} → ${tripView.memberById(settlement.toMemberId).name}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.captionMuted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label, tone: tone),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
