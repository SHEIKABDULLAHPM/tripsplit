import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../domain/funding_exception.dart';
import '../domain/funding_info.dart';
import '../providers/funding_providers.dart';

/// Sanitized riverpod future for order history.
final fundingHistoryProvider = FutureProvider<List<FundingOrder>>(
  (ref) => ref.watch(fundingRepositoryProvider).fetchHistory(),
);

/// Funding order history. Data is read-only and comes from the funding server.
class FundingHistoryScreen extends ConsumerWidget {
  const FundingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(fundingHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Funding history')),
      body: SafeArea(
        bottom: true,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            final message = error is FundingException
                ? error.message
                : 'An internet connection is required to load funding '
                    'history.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMuted,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.tonal(
                      onPressed: () => ref.invalidate(fundingHistoryProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          },
          data: (orders) {
            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('No funding yet', style: theme.textTheme.sectionTitle),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Your funding orders will appear here.',
                      style: theme.textTheme.bodyMuted,
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.screenVertical,
              ),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final order = orders[index];
                return _HistoryCard(order: order);
              },
            );
          },
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.order});

  final FundingOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = switch (order.status) {
      FundingStatus.verified => AppColors.success,
      FundingStatus.refunded => AppColors.warning,
      FundingStatus.failed => AppColors.error,
      FundingStatus.cancelled ||
      FundingStatus.expired => theme.colorScheme.onSurfaceVariant,
      _ => AppColors.info,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.type.displayName,
                    style: theme.textTheme.subtitle,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    order.status.wire,
                    style: theme.textTheme.labelMedium?.copyWith(color: colour),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              MoneyCalculator.format(order.amountMinor),
              style: theme.textTheme.titleBold.copyWith(color: colour),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(order.publicReference, style: theme.textTheme.captionMuted),
            if (order.createdAt != null)
              Text(
                _formatDate(order.createdAt!),
                style: theme.textTheme.captionMuted,
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(String iso) {
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = parsed.hour.toString().padLeft(2, '0');
  final mm = parsed.minute.toString().padLeft(2, '0');
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}, $hh:$mm';
}
