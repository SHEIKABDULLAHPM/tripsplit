import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic colors used to communicate financial states across the app.
///
/// Defined as a [ThemeExtension] so every widget reads states from the active
/// theme rather than hardcoding values, keeping the light (and any future)
/// theme consistent.
@immutable
class AppFinancialColors extends ThemeExtension<AppFinancialColors> {
  const AppFinancialColors({
    required this.receives,
    required this.receivesContainer,
    required this.onReceivesContainer,
    required this.owes,
    required this.owesContainer,
    required this.onOwesContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  /// Money a member is owed (they will receive cash).
  final Color receives;
  final Color receivesContainer;
  final Color onReceivesContainer;

  /// Money a member owes (they should pay cash out).
  final Color owes;
  final Color owesContainer;
  final Color onOwesContainer;

  /// Neutral informational tones (e.g. fully settled, read-only totals).
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  static const AppFinancialColors light = AppFinancialColors(
    receives: AppColors.receives,
    receivesContainer: AppColors.receivesContainer,
    onReceivesContainer: AppColors.onReceivesContainer,
    owes: AppColors.owes,
    owesContainer: AppColors.owesContainer,
    onOwesContainer: AppColors.onOwesContainer,
    info: AppColors.tertiary,
    infoContainer: AppColors.tertiaryContainer,
    onInfoContainer: AppColors.onTertiaryContainer,
  );

  @override
  AppFinancialColors copyWith({
    Color? receives,
    Color? receivesContainer,
    Color? onReceivesContainer,
    Color? owes,
    Color? owesContainer,
    Color? onOwesContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
  }) => AppFinancialColors(
    receives: receives ?? this.receives,
    receivesContainer: receivesContainer ?? this.receivesContainer,
    onReceivesContainer: onReceivesContainer ?? this.onReceivesContainer,
    owes: owes ?? this.owes,
    owesContainer: owesContainer ?? this.owesContainer,
    onOwesContainer: onOwesContainer ?? this.onOwesContainer,
    info: info ?? this.info,
    infoContainer: infoContainer ?? this.infoContainer,
    onInfoContainer: onInfoContainer ?? this.onInfoContainer,
  );

  @override
  AppFinancialColors lerp(AppFinancialColors? other, double t) {
    if (other == null) return this;
    return AppFinancialColors(
      receives: Color.lerp(receives, other.receives, t)!,
      receivesContainer: Color.lerp(
        receivesContainer,
        other.receivesContainer,
        t,
      )!,
      onReceivesContainer: Color.lerp(
        onReceivesContainer,
        other.onReceivesContainer,
        t,
      )!,
      owes: Color.lerp(owes, other.owes, t)!,
      owesContainer: Color.lerp(owesContainer, other.owesContainer, t)!,
      onOwesContainer: Color.lerp(onOwesContainer, other.onOwesContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

/// Typed accessor so widgets can read financial state colors from the theme.
extension AppFinancialColorsContext on BuildContext {
  AppFinancialColors get financial =>
      Theme.of(this).extension<AppFinancialColors>() ??
      AppFinancialColors.light;
}
