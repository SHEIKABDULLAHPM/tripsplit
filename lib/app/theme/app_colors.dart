import 'package:flutter/material.dart';

/// Centralized brand color palette.
///
/// All widgets must reference colors through this class (or the Material 3
/// [ColorScheme] built from it) instead of hardcoding color values.
abstract final class AppColors {
  AppColors._();

  // Brand / primary
  static const Color primary = Color(0xFF2E7D57);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFB0F0CF);
  static const Color onPrimaryContainer = Color(0xFF002115);

  // Secondary
  static const Color secondary = Color(0xFF4D6360);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFCFE8E2);
  static const Color onSecondaryContainer = Color(0xFF09201D);

  // Tertiary
  static const Color tertiary = Color(0xFF3C6473);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFC0E9FB);
  static const Color onTertiaryContainer = Color(0xFF001F29);

  // Surface / background
  static const Color surface = Color(0xFFF7FAF6);
  static const Color onSurface = Color(0xFF191C1A);
  static const Color surfaceVariant = Color(0xFFDBE5DE);
  static const Color onSurfaceVariant = Color(0xFF3F4944);
  static const Color surfaceContainerHighest = Color(0xFFDBE5DE);
  static const Color outline = Color(0xFF6F7974);
  static const Color outlineVariant = Color(0xFFBFC9C3);
  static const Color background = Color(0xFFF7FAF6);

  // Fixed surfaces
  static const Color surfaceTint = Color(0xFF2E7D57);
  static const Color surface1 = Color(0xFFEFF3EE);
  static const Color surface2 = Color(0xFFEBEFE9);

  // Semantic
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);

  // Financial states – monetary role tokens used via AppFinancialColors
  static const Color receives = Color(0xFF1A6B3C);
  static const Color receivesContainer = Color(0xFFD1F3DF);
  static const Color onReceivesContainer = Color(0xFF00210F);

  static const Color owes = Color(0xFF8A5000);
  static const Color owesContainer = Color(0xFFFFDCBB);
  static const Color onOwesContainer = Color(0xFF2C1600);

  static const Color info = Color(0xFF3C6473);
  static const Color infoContainer = Color(0xFFC0E9FB);
  static const Color onInfoContainer = Color(0xFF001F29);

  // Misc
  static const Color scrim = Color(0xFF000000);
  static const Color inverseSurface = Color(0xFF2E312F);
  static const Color onInverseSurface = Color(0xFFF0F1EC);
  static const Color inversePrimary = Color(0xFF95D4B4);
}
