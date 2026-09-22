/// Client-side funding configuration.
///
/// No secrets live here — only the server address and the version of the
/// terms the app displays. The server re-validates both when an order is
/// created. The production backend is the default so every build talks to
/// the deployed funding service out of the box; point a local build at a
/// different server (for example the sandbox) with
/// `--dart-define=FUNDING_API_BASE_URL=http://<host>:8080`.
abstract final class FundingConfig {
  FundingConfig._();

  static const String _definedBaseUrl = String.fromEnvironment(
    'FUNDING_API_BASE_URL',
  );

  /// Production funding service (Render). Used whenever no explicit
  /// `FUNDING_API_BASE_URL` was provided at build time.
  static const String productionApiBaseUrl =
      'https://tripsplit-funding.onrender.com';

  /// Terms version shipped with this build (must match the server's
  /// CURRENT_TERMS_VERSION).
  static const String currentTermsVersion = '2026-09-21';

  static const String contactEmail = 'tripsplit.me@gmail.com';

  /// The funding service base URL.
  static String get apiBaseUrl =>
      _definedBaseUrl.isNotEmpty ? _definedBaseUrl : productionApiBaseUrl;
}
