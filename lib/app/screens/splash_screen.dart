import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferences/onboarding_preferences.dart';
import '../router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/brand_lockup.dart';

/// Branded splash screen shown at `/splash`.
///
/// Presents the official TripSplit logo (symbol + wordmark + tagline) on the
/// asset's white canvas, holds long enough to read the onboarding flag, then
/// routes first-time users through Welcome → Onboarding and returning users
/// straight to Home. Navigation uses `go`, replacing Splash in the stack so
/// back never returns here.
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: LayoutBuilder(
                builder: (context, constraints) => SvgPicture.asset(
                  tripSplitLogoSvg,
                  // Cap width so the square logo never overruns tall or
                  // narrow screens; height follows the intrinsic ratio.
                  width: (constraints.maxWidth * 0.84).clamp(0, 460),
                ),
              ),
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
  );
}
