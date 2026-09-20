import 'package:flutter/material.dart';

import '../../app/theme/app_financial_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';

/// Visual tone of a [StatusChip].
enum StatusTone {
  /// Positive state (e.g. "Paid", "Receives").
  success,

  /// Attention-worthy state (e.g. "Partial", "Owes").
  warning,

  /// Neutral informational state (e.g. "Balanced", "Outstanding").
  neutral,

  /// Branded informational state.
  info,

  /// Destructive state (e.g. "Remove").
  danger,
}

/// Small uppercase pill label used to surface a status at a glance.
///
/// Color must never be the only signal: the pill always carries the text label
/// and is exposed to screen readers via [Semantics].
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financial = context.financial;

    final (background, foreground) = switch (tone) {
      StatusTone.success => (
        financial.receivesContainer,
        financial.onReceivesContainer,
      ),
      StatusTone.warning => (
        financial.owesContainer,
        financial.onOwesContainer,
      ),
      StatusTone.info => (financial.infoContainer, financial.onInfoContainer),
      StatusTone.danger => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
      StatusTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurface,
      ),
    };

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
