import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferences/onboarding_preferences.dart';
import '../router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/brand_lockup.dart';

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

const _pages = [
  _OnboardingPageData(
    icon: Icons.luggage_outlined,
    title: 'Plan the budget',
    description:
        'Set a planned group budget and record every member’s contribution '
        'as cash comes into the trip pool.',
  ),
  _OnboardingPageData(
    icon: Icons.group_outlined,
    title: 'Split expenses fairly',
    description:
        'Add the trip members, record who paid, and TripSplit divides every '
        'expense equally between the participants.',
  ),
  _OnboardingPageData(
    icon: Icons.swap_horiz,
    title: 'Settle up, offline',
    description:
        'See exactly who owes whom and record payments — cash or digital — '
        'with everything stored privately on your device.',
  ),
];

/// Three-step onboarding tour at `/onboarding`.
///
/// Works offline, never touches the network, and persists "completed" so a
/// returning user goes Splash → Home instead of repeating the tour. Reaching
/// Home marks it done even when replaying from the Home menu.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static final _totalPages = _pages.length;

  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  bool get _isLastPage => _index == _totalPages - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() async {
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    setState(() => _finishing = true);
    await OnboardingPrefs.markCompleted();
    if (mounted) {
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
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BrandLockup(
                  size: BrandLockupSize.small,
                  showWordmark: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _totalPages,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _totalPages,
                  onPageChanged: (page) => setState(() => _index = page),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: AppIconSizes.xl * 1.75,
                              height: AppIconSizes.xl * 1.75,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                page.icon,
                                size: AppIconSizes.xl + 8,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            page.title,
                            style: theme.textTheme.screenTitle.copyWith(
                              fontSize: 28,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            page.description,
                            style: theme.textTheme.bodyMuted.copyWith(
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _finishing ? null : _skip,
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _finishing
                        ? null
                        : _isLastPage
                        ? _finish
                        : () => _goToPage(_index + 1),
                    icon: Icon(_isLastPage ? Icons.check : Icons.arrow_forward),
                    label: Text(_isLastPage ? 'Get started' : 'Next'),
                  ),
                ],
              ),
              if (_index > 0)
                Semantics(
                  button: true,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _goToPage(_index - 1),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
