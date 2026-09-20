import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the first-launch / onboarding flow.
///
/// A returning user is one who completed (or explicitly skipped) onboarding.
/// Completion is stored locally and never sent anywhere.
abstract final class OnboardingPrefs {
  OnboardingPrefs._();

  static const String _completedKey = 'onboarding_completed';

  /// Whether onboarding has been completed or skipped.
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  /// Marks onboarding as done so returning users land straight on Home.
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
