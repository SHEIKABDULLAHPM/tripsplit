import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Official TripSplit logo artwork.
///
/// The full asset (symbol + wordmark + tagline, on white) is used for hero
/// brand moments like the splash screen. The symbol-only variant is used
/// wherever just the mark fits, e.g. app bars and compact lockups.
const String tripSplitLogoSvg = 'assets/logo/tripsplit-logo.svg';
const String tripSplitSymbolSvg = 'assets/logo/tripsplit-symbol.svg';

/// Wordmark colors from the official logotype ("Trip" navy, "Split" blue).
const Color _tripColor = Color(0xFF142B4A);
const Color _splitColor = Color(0xFF1678EF);

/// The TripSplit symbol rendered from the official SVG mark.
///
/// Sized to the given box with [BoxFit.contain] so it never distorts.
class TripSplitMark extends StatelessWidget {
  const TripSplitMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'TripSplit',
    child: SvgPicture.asset(
      tripSplitSymbolSvg,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => const SizedBox.shrink(),
    ),
  );
}

/// The "TripSplit" logotype as rendered text, matching the official asset's
/// two-tone wordmark (navy "Trip", blue "Split").
class TripSplitWordmark extends StatelessWidget {
  const TripSplitWordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.0,
    );
    return Text.rich(
      const TextSpan(
        children: [
          TextSpan(
            text: 'Trip',
            style: TextStyle(color: _tripColor),
          ),
          TextSpan(
            text: 'Split',
            style: TextStyle(color: _splitColor),
          ),
        ],
      ),
      style: base,
      textAlign: TextAlign.center,
    );
  }
}

/// Brand mark + wordmark used by Splash, Welcome and Onboarding.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.size = BrandLockupSize.hero,
    this.showWordmark = true,
  });

  /// Small (inline), medium (headers) or hero (splash) presentation.
  final BrandLockupSize size;

  /// Whether to render the "TripSplit" wordmark under the mark.
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final markSize = switch (size) {
      BrandLockupSize.small => 48.0,
      BrandLockupSize.medium => 88.0,
      BrandLockupSize.hero => 112.0,
    };
    final iconSize = switch (size) {
      BrandLockupSize.small => 26.0,
      BrandLockupSize.medium => 44.0,
      BrandLockupSize.hero => 56.0,
    };
    final wordmarkSize = switch (size) {
      BrandLockupSize.small => 22.0,
      BrandLockupSize.medium => 38.0,
      BrandLockupSize.hero => 48.0,
    };
    final gap = switch (size) {
      BrandLockupSize.small => AppSpacing.sm,
      BrandLockupSize.medium => AppSpacing.xl,
      BrandLockupSize.hero => AppSpacing.xxl,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Center(child: TripSplitMark(size: iconSize)),
        ),
        if (showWordmark) ...[
          SizedBox(height: gap),
          TripSplitWordmark(fontSize: wordmarkSize),
        ],
      ],
    );
  }
}

enum BrandLockupSize { small, medium, hero }
