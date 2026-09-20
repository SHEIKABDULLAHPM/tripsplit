import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferences/onboarding_preferences.dart';
import '../router.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/brand_lockup.dart';

/// Welcome screen for first-time users at `/welcome`.
///
/// Introduces the app in one screen, then funnels into the three-step
/// onboarding tour. "Skip tour" marks onboarding complete so returning users
/// will not be asked again.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _startTour(BuildContext context) {
    context.go(AppRoutes.onboarding);
  }

  Future<void> _skipTour(BuildContext context) async {
    await OnboardingPrefs.markCompleted();
    if (context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandLockup(size: BrandLockupSize.medium),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Every rupee, accounted for.',
                        style: theme.textTheme.screenTitle.copyWith(
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'TripSplit is an offline-first way to share trip '
                        'expenses — plan a budget, split costs evenly, and '
                        'settle up without losing track.',
                        style: theme.textTheme.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const _ValueProp(
                        icon: Icons.luggage_outlined,
                        text: 'Set a group budget and track contributions',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _ValueProp(
                        icon: Icons.receipt_long_outlined,
                        text: 'Record expenses and split them fairly',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _ValueProp(
                        icon: Icons.swap_horiz,
                        text: 'See balances and settle up easily',
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _startTour(context),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Get started'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => _skipTour(context),
                child: const Text('Skip tour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueProp extends StatelessWidget {
  const _ValueProp({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
