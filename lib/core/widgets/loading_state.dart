import 'package:flutter/material.dart';

import '../../app/theme/app_icon_sizes.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

/// Centered loading placeholder reused as the default async loading state.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: AppIconSizes.lg,
              height: AppIconSizes.lg,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(label, style: theme.textTheme.bodyMuted),
          ],
        ),
      ),
    );
  }
}
