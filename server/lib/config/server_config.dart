/// Runtime configuration for the funding server, sourced from environment
/// variables so no secrets ship in the repository or in the Flutter client.
///
/// Environment separation:
///  - Development / Staging use Razorpay **test** keys
///    (`RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` from the dashboard "Keys" tab
///    with `Test Mode` enabled) and `FUNDING_ENV=development|staging`.
///  - Production uses live keys and `FUNDING_ENV=production`.
///
/// Only the public Key Id may ever reach the mobile client — and even then it
/// is served by this backend at order creation, never embedded in the APK.
library;

import 'env_file.dart';

/// Server-side configuration.
class ServerConfig {
  final int port;
  final String dbPath;
  final String environment;
  final String gatewayMode;

  /// Secret used to verify gateway webhook signatures (simulated gateway uses
  /// it for its own HMAC; Razorpay uses the dashboard webhook secret).
  final String webhookSecret;

  /// Public Razorpay Key Id (never a secret). Optional for the simulator.
  final String? razorpayKeyId;

  /// Razorpay Key Secret — server-only, never exposed to any client.
  final String? razorpayKeySecret;

  /// Razorpay API base URL (overridable for proxies/mocks; default is the real
  /// API). Never includes a key or secret.
  final String razorpayApiBase;

  final String? adminKey;
  final String currentTermsVersion;
  final String publicBaseUrl;
  final int maxBodyBytes;
  final int createdAt;

  const ServerConfig({
    required this.port,
    required this.dbPath,
    required this.environment,
    required this.gatewayMode,
    required this.webhookSecret,
    required this.razorpayKeyId,
    required this.razorpayKeySecret,
    required this.razorpayApiBase,
    required this.adminKey,
    required this.currentTermsVersion,
    required this.publicBaseUrl,
    required this.maxBodyBytes,
    required this.createdAt,
  });

  bool get isSimulated => gatewayMode == 'simulated';

  /// Reads configuration from the environment with production-safe defaults
  /// for local development.
  ///
  /// Configuration is resolved by [effectiveEnvironment]: a git-ignored `.env`
  /// file supplies defaults and the process environment wins. [envFilePath]
  /// forces a specific file and [environment] substitutes the process
  /// environment entirely (used by tests).
  factory ServerConfig.fromEnvironment({
    String? envFilePath,
    Map<String, String>? environment,
  }) {
    final all = effectiveEnvironment(path: envFilePath, platform: environment);

    String? env(String name) {
      final value = all[name];
      return (value == null || value.isEmpty) ? null : value;
    }

    final environmentName = env('FUNDING_ENV') ?? 'test';
    final gatewayMode = env('GATEWAY_MODE') ?? 'simulated';
    final webhookSecret =
        env('RAZORPAY_WEBHOOK_SECRET') ?? env('FUNDING_WEBHOOK_SECRET');
    final keyId = env('RAZORPAY_KEY_ID');
    final keySecret = env('RAZORPAY_KEY_SECRET');
    if (gatewayMode == 'razorpay') {
      if (keyId == null || keyId.isEmpty) {
        throw StateError('RAZORPAY_KEY_ID is required in razorpay mode');
      }
      if (keySecret == null || keySecret.isEmpty) {
        throw StateError('RAZORPAY_KEY_SECRET is required in razorpay mode');
      }
      if (webhookSecret == null || webhookSecret.isEmpty) {
        throw StateError(
          'RAZORPAY_WEBHOOK_SECRET is required in razorpay mode',
        );
      }
    } else if (gatewayMode != 'simulated') {
      throw StateError('GATEWAY_MODE must be "simulated" or "razorpay"');
    }
    return ServerConfig(
      port: int.tryParse(env('PORT') ?? '') ?? 8080,
      dbPath: env('FUNDING_DB_PATH') ?? _databasePath(env) ?? 'funding.sqlite3',
      environment: environmentName,
      gatewayMode: gatewayMode,
      webhookSecret:
          webhookSecret ?? 'dev-only-simulated-secret-do-not-use-in-prod',
      razorpayKeyId: keyId,
      razorpayKeySecret: keySecret,
      razorpayApiBase: env('RAZORPAY_API_BASE') ?? 'https://api.razorpay.com',
      adminKey: env('FUNDING_ADMIN_KEY'),
      currentTermsVersion: env('CURRENT_TERMS_VERSION') ?? '2026-09-21',
      publicBaseUrl: env('FUNDING_PUBLIC_BASE_URL') ?? 'http://localhost:8080',
      maxBodyBytes: int.tryParse(env('MAX_BODY_BYTES') ?? '') ?? 1 << 20,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Resolves the SQLite database location from `DATABASE_URL` when present.
/// This deployment uses embedded SQLite, so only paths and `file:` URLs are
/// supported — remote database URLs are intentionally rejected rather than
/// silently ignored.
String? _databasePath(String? Function(String name) env) {
  final url = env('DATABASE_URL');
  if (url == null) return null;
  if (url.startsWith('file:')) {
    return url.substring('file:'.length);
  }
  if (url.startsWith('http://') || url.startsWith('https://')) {
    throw StateError(
      'DATABASE_URL must point at an embedded SQLite file, not a remote server',
    );
  }
  return url;
}
