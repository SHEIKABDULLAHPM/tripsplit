/// Centralized spacing scale.
///
/// Widgets should use these constants instead of raw numeric padding/margin
/// values to keep the layout consistent and themeable.
abstract final class AppSpacing {
  AppSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  /// Screen-level horizontal padding.
  static const double screenHorizontal = lg;

  /// Screen-level vertical padding.
  static const double screenVertical = xl;

  /// Corner radius used by cards and sheets.
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
}
