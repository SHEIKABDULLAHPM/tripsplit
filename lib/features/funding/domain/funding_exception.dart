/// Errors surfaced by the funding feature.
///
/// Funding is the only online feature; it must fail politely and never block
/// offline trip functionality.
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Categorizes why a funding network call failed.
enum FundingFailureKind {
  offline,
  serverUnreachable,
  backendUnreachable,
  timeout,
  server,
  malformedResponse,
  razorpayOrderFailed,
  checkoutInitializationFailed,
}

/// A funding operation failure with a message safe to show the user.
class FundingException implements Exception {
  const FundingException(this.kind, this.message);

  final FundingFailureKind kind;
  final String message;

  @override
  String toString() => 'FundingException($kind): $message';
}

/// Logs a funding debug message (development builds only — never logs
/// secrets, and never emitted into release logs).
void fundingLog(String message) {
  if (kDebugMode) {
    developer.log('[FUNDING] $message', name: 'funding');
  }
}

/// Logs a funding error (development builds only — never logs secrets, and
/// never emitted into release logs).
void fundingLogError(String message, [Object? error]) {
  if (kDebugMode) {
    developer.log('[FUNDING][ERROR] $message', name: 'funding', error: error);
  }
}

/// The offline message used whenever funding needs the network.
const String fundingRequiresInternet =
    'An internet connection is required to process funding. '
    'Please connect to the internet and try again.';

/// Server is reachable but returned an error.
const String fundingServerUnavailable =
    'We couldn\'t connect to the payment service. Please try again.';

/// The backend server is not reachable.
const String fundingBackendUnreachable =
    'The funding server is not reachable. Please try again later.';

/// Request timed out.
const String fundingTimedOut =
    'The payment service took too long to respond. Please try again.';

/// Razorpay order creation failed on the server.
const String fundingRazorpayOrderFailed =
    'Payment order creation failed. Please try again.';
