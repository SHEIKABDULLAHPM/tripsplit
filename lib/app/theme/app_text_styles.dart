import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic text-style shortcuts.
///
/// Widgets should reference these getters instead of ad-hoc
/// `Theme.of(context).textTheme.copyWith(...)` calls.
extension AppTextStylesX on TextTheme {
  // ─────────────────────────────────────────────────────────────────────────
  // App-brand hero
  // ─────────────────────────────────────────────────────────────────────────

  /// Large logo / splash headline.
  TextStyle get brandHeadline =>
      headlineLarge!.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5);

  // ─────────────────────────────────────────────────────────────────────────
  // Screen-level hierarchy
  // ─────────────────────────────────────────────────────────────────────────

  /// AppBar / page-level title (replaces old `title` getter).
  TextStyle get screenTitle => headlineSmall!.copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
  );

  /// Section heading inside a scrollable card list.
  TextStyle get sectionTitle =>
      titleLarge!.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.0);

  // ─────────────────────────────────────────────────────────────────────────
  // Legacy aliases kept for incremental migration – prefer the new names
  // ─────────────────────────────────────────────────────────────────────────

  TextStyle get title => screenTitle;
  TextStyle get titleBold =>
      headlineSmall!.copyWith(fontWeight: FontWeight.bold);

  // ─────────────────────────────────────────────────────────────────────────
  // Body / detail text
  // ─────────────────────────────────────────────────────────────────────────

  TextStyle get subtitle => titleMedium!;
  TextStyle get bodyMuted =>
      bodyMedium!.copyWith(color: AppColors.onSurfaceVariant);
  TextStyle get captionMuted =>
      bodySmall!.copyWith(color: AppColors.onSurfaceVariant);
  TextStyle get labelMuted =>
      labelMedium!.copyWith(color: AppColors.onSurfaceVariant);

  // ─────────────────────────────────────────────────────────────────────────
  // Financial-specific styles
  // ─────────────────────────────────────────────────────────────────────────

  /// Label above a money figure inside a stat card.
  TextStyle get statLabel => labelMedium!.copyWith(
    color: AppColors.onSurfaceVariant,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w500,
  );

  /// Value beside/under a stat label (e.g. "₹1,200").
  TextStyle get statValue => titleMedium!.copyWith(fontWeight: FontWeight.w600);

  /// The hero-style money figure in a detail sheet or summary card.
  TextStyle get moneyHero => headlineMedium!.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// A strong money figure that is not quite the hero (e.g. balance amount
  /// on a card).
  TextStyle get moneyStrong =>
      titleLarge!.copyWith(fontWeight: FontWeight.bold);

  // ─────────────────────────────────────────────────────────────────────────
  // State / status helpers (content-colored, small)
  // ─────────────────────────────────────────────────────────────────────────

  TextStyle get positiveLabel => labelSmall!.copyWith(
    color: AppColors.receives,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  TextStyle get warningLabel => labelSmall!.copyWith(
    color: AppColors.owes,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  TextStyle get errorLabel => labelSmall!.copyWith(
    color: AppColors.error,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}
