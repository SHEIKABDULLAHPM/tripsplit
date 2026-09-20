import 'package:flutter/material.dart';

/// Canonical corner-radius scale.
///
/// Preferred over hardcoded radii so cards, buttons, inputs and sheets share a
/// single visual language. (Legacy radii in [AppSpacing] are kept only for
/// compatibility; new code uses [AppRadius].)
abstract final class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;

  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allXl = BorderRadius.all(Radius.circular(xl));

  /// Only top corners are rounded; used for modal bottom sheets.
  static const BorderRadius topLg = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}
