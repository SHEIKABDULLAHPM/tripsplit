/// Centralized elevation scale.
///
/// Surfaces reference these values so shadow depth stays intentional:
/// 0–1 resting surfaces, 2–4 cards/popovers, 8 modal/dialog grade.
abstract final class AppElevation {
  AppElevation._();

  static const double none = 0.0;
  static const double xs = 1.0;
  static const double sm = 2.0;
  static const double md = 4.0;
  static const double lg = 8.0;
}
