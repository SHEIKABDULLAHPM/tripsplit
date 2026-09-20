import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../domain/funding_exception.dart';
import '../domain/funding_info.dart';
import '../providers/funding_providers.dart';

/// Receipt/outcome screen shown after a checkout.
///
/// Always re-fetches the authoritative status from the server; handles the
/// "payment made but response lost" case by allowing a retry.
class FundingResultScreen extends ConsumerWidget {
  const FundingResultScreen({super.key, required this.publicReference});

  final String publicReference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(_statusProvider(publicReference));
    return Scaffold(
      appBar: AppBar(title: const Text('Funding outcome')),
      body: SafeArea(
        bottom: true,
        child: future.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            final message = error is FundingException
                ? error.message
                : 'Could not load the order status.';
            return _OutcomeErrorBody(
              message: message,
              onRetry: () => ref.invalidate(_statusProvider(publicReference)),
              onDone: () => context.go(AppRoutes.funding),
            );
          },
          data: (order) => _buildBody(context, order),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FundingOrder order) {
    if (order.status.isVerified) {
      return _ReceiptBody(order: order);
    }
    if (order.status.isRefunded) {
      return _ReceiptBody(order: order, refunded: true);
    }
    if (order.status.isFailed) {
      return _OutcomeBody(
        icon: Icons.error_outline,
        title: 'Payment failed',
        message:
            'The payment was not completed and your order has been closed. '
            'No money was charged.',
        order: order,
      );
    }
    if (order.status.isCancelled) {
      return _OutcomeBody(
        icon: Icons.close,
        title: 'Checkout cancelled',
        message: 'You cancelled the checkout. No money was charged.',
        order: order,
      );
    }
    return _PendingBody(order: order);
  }
}

final _statusProvider = FutureProvider.autoDispose.family<FundingOrder, String>(
  (ref, reference) =>
      ref.watch(fundingRepositoryProvider).fetchStatus(reference),
);

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.order, this.refunded = false});

  final FundingOrder order;
  final bool refunded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = refunded ? AppColors.warning : AppColors.success;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.screenVertical,
      ),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              refunded ? Icons.receipt_long : Icons.check_rounded,
              size: 40,
              color: colour,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          refunded ? 'Order refunded' : 'Payment received',
          textAlign: TextAlign.center,
          style: theme.textTheme.screenTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Thank you for supporting TripSplit.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xl),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amount', style: theme.textTheme.bodyMuted),
                    Text(
                      '${MoneyCalculator.format(order.amountMinor)} '
                      '${order.currency}',
                      style: theme.textTheme.subtitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xl),
                _ReceiptRow(
                  label: 'Support type',
                  value: order.type.displayName,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ReceiptRow(label: 'Status', value: order.status.wire),
                const SizedBox(height: AppSpacing.sm),
                _ReceiptRow(label: 'Reference', value: order.publicReference),
                if (order.verifiedAt != null)
                  _ReceiptRow(
                    label: 'Verified',
                    value: _formatDate(order.verifiedAt!),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _ReceiptRow(label: 'Terms', value: order.termsVersion),
                if (order.note.isNotEmpty) ...[
                  const Divider(height: AppSpacing.xl),
                  Text(order.note, style: theme.textTheme.captionMuted),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => context.go(AppRoutes.funding),
          child: const Text('Done'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.push(AppRoutes.fundingHistory),
          child: const Text('View funding history'),
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.captionMuted),
        const SizedBox(width: AppSpacing.lg),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _OutcomeBody extends StatelessWidget {
  const _OutcomeBody({
    required this.icon,
    required this.title,
    required this.message,
    this.order,
  });

  final IconData icon;
  final String title;
  final String message;
  final FundingOrder? order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Center(
          child: Icon(
            icon,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.screenTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMuted,
        ),
        if (order != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            order!.publicReference,
            textAlign: TextAlign.center,
            style: theme.textTheme.captionMuted,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => context.go(AppRoutes.funding),
          child: const Text('Back to funding'),
        ),
      ],
    );
  }
}

class _OutcomeErrorBody extends StatelessWidget {
  const _OutcomeErrorBody({
    required this.message,
    required this.onRetry,
    required this.onDone,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Center(
          child: Icon(
            Icons.wifi_off,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onDone, child: const Text('Back')),
      ],
    );
  }
}

class _PendingBody extends ConsumerStatefulWidget {
  const _PendingBody({required this.order});

  final FundingOrder order;

  @override
  ConsumerState<_PendingBody> createState() => _PendingBodyState();
}

class _PendingBodyState extends ConsumerState<_PendingBody> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment pending',
          textAlign: TextAlign.center,
          style: theme.textTheme.screenTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your payment (${widget.order.publicReference}) is still being '
          'verified. This usually completes within a few seconds.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => ref.invalidate(
            _statusProvider(widget.order.publicReference),
          ),
          child: const Text('Check again'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.go(AppRoutes.funding),
          child: const Text('Back to funding'),
        ),
      ],
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
