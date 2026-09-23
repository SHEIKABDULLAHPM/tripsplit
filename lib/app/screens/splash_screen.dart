import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferences/onboarding_preferences.dart';
import '../router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/brand_lockup.dart' show tripSplitLogoMark;

/// Branded splash screen shown at `/splash`.
///
/// Presents the official TripSplit logo at a reduced hero size (roughly 58% of
/// the available width, capped) so the mark reads as a deliberate brand moment
/// rather than filling the viewport. A [FittedBox] scales the whole lockup
/// down on short screens (e.g. landscape) so it always fits. Holds long enough
/// to read the onboarding flag, then routes first-time users through Welcome →
/// Onboarding and returning users straight to Home. Navigation uses `go`,
/// replacing Splash in the stack so back never returns here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_started) {
      return;
    }
    _started = true;
    // Short minimum hold so the splash reads as intentional, not a white
    // flicker. Overlaps the preference read so it adds no real latency.
    final completedFuture = OnboardingPrefs.isCompleted();
    final delay = Future<void>.delayed(const Duration(milliseconds: 650));
    final completed = await completedFuture;
    await delay;
    if (!mounted) {
      return;
    }
    context.go(completed ? AppRoutes.home : AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // The logo asset ships on a pure-white canvas; keep the splash white so
    // the artwork sits seamlessly without a visible box.
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    tripSplitLogoMark,
                    // Reduced hero size: ~58% of the available width, capped.
                    // Height follows the intrinsic aspect ratio. FittedBox
                    // shrinks this whole lockup only when a short viewport
                    // (e.g. landscape) cannot fit the logo plus indicator.
                    width: (constraints.maxWidth * 0.58).clamp(0, 320),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
