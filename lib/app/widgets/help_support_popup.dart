import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/funding/config/funding_config.dart';
import '../router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'brand_lockup.dart';

/// Tracks whether the Help & Support popup has been shown this app session.
///
/// A single flag keeps the popup from duplicating whenever the user returns to
/// Home during the same launch.
class HelpSupportPopupFlag extends Notifier<bool> {
  @override
  bool build() => false;

  void markShown() => state = true;
}

final helpSupportPopupFlagProvider =
    NotifierProvider<HelpSupportPopupFlag, bool>(HelpSupportPopupFlag.new);

/// Shows the Help & Support popup exactly once per app launch (when Home is
/// first reached). Returns immediately if it was already shown.
Future<void> showHelpSupportPopupIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(helpSupportPopupFlagProvider)) return;
  ref.read(helpSupportPopupFlagProvider.notifier).markShown();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    useSafeArea: true,
    builder: (_) => const HelpSupportPopup(),
  );
}

/// The Help & Support popup shown on app open.
///
/// Designed as a compact, dismissible dialog: it never blocks the app longer
/// than the user wants, scales to small screens via an internal scroll view,
/// and offers both a clear close action and a fast path to the funding screen.
class HelpSupportPopup extends StatelessWidget {
  const HelpSupportPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Center(child: TripSplitMark(size: 32)),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Help & Support', style: theme.textTheme.sectionTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'TripSplit keeps every trip, expense and settlement on this '
                'device — no account needed, and it stays free forever. '
                'Need a hand, or want to support its ongoing development? '
                'Both live in the app menu, and you can email '
                '${FundingConfig.contactEmail} anytime.',
                style: theme.textTheme.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.funding);
                    },
                    child: const Text('Support the project'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'),
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
