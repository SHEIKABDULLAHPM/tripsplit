import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/funding_config.dart';
import '../data/connectivity_checker.dart';
import '../data/funding_api_client.dart';
import '../data/funding_repository.dart';
import '../data/razorpay_service.dart';
import '../domain/razorpay_checkout.dart';

/// API client for the funding service.
final fundingApiClientProvider = Provider<FundingApiClient>(
  (ref) => FundingApiClient(baseUrl: FundingConfig.apiBaseUrl),
);

/// Repository for funding operations.
///
/// This provider depends only on [fundingApiClientProvider] — it never touches
/// the application database providers, by design.
final fundingRepositoryProvider = Provider<FundingRepository>(
  (ref) => FundingRepository(ref.watch(fundingApiClientProvider)),
);

/// Hosted-checkout launcher.
///
/// Overridable in tests with a fake that never touches the razorpay_flutter
/// plugin (and therefore never a real payment).
final razorpayCheckoutLauncherProvider = Provider<RazorpayCheckoutLauncher>(
  (ref) => RazorpayService(),
);

/// Connectivity checker for proactive network detection.
///
/// Overridable in tests with a fake that never touches platform channels.
final connectivityCheckerProvider = Provider<ConnectivityChecker>(
  (ref) => ConnectivityPlusChecker(),
);
