import 'package:flutter/foundation.dart';

/// Client-side funding configuration.
///
/// No secrets live here — only the server address and the version of the
/// terms the app displays. The server re-validates both when an order is
/// created. Point the app at the funding server with
/// `--dart-define=FUNDING_API_BASE_URL=http://<host>:8080`.
abstract final class FundingConfig {
  FundingConfig._();

  static const String _definedBaseUrl = String.fromEnvironment(
    'FUNDING_API_BASE_URL',
  );

  /// Terms version shipped with this build (must match the server's
  /// CURRENT_TERMS_VERSION).
  static const String currentTermsVersion = '2026-09-01';

  static const String contactEmail = 'support@tripsplit.in';

  /// The funding service base URL.
  static String get apiBaseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }
    if (!kIsWeb) {
      return 'http://10.0.2.2:8080'; // Android emulator host loopback.
    }
    return 'http://localhost:8080';
  }
}
