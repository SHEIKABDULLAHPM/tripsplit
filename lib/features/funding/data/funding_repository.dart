import '../config/funding_config.dart';
import '../domain/funding_exception.dart';
import '../domain/funding_info.dart';
import 'funding_api_client.dart';

/// Repository for the funding service.
///
/// Every operation is a network call to the funding server; there is no local
/// caching and no interaction with the trip database. Charge amounts are
/// always the server's: [FundingOrder.amountMinor] is what gets displayed,
/// never the client-side [FundingType.displayRupees].
class FundingRepository {
  FundingRepository(this._client);

  final FundingApiClient _client;

  /// Creates a funding order for [type].
  ///
  /// [idempotencyKey] shields against double-taps: the server returns the
  /// existing order when the key repeats.
  Future<FundingOrder> createOrder(
    FundingType type, {
    required String idempotencyKey,
    String? termsVersion,
  }) async {
    final json = await _client.post('/api/v1/funding/orders', {
      'fundingType': type.wire,
      'termsVersion': termsVersion ?? FundingConfig.currentTermsVersion,
      'accepted': true,
      'idempotencyKey': idempotencyKey,
    });
    return mapOrder(json);
  }

  /// Finalizes a checkout through the sandbox simulator (sandbox servers
  /// only; the real gateway path replaces this).
  Future<FundingOrder> simulateCheckout(
    String publicReference,
    String outcome,
  ) async {
    final json = await _client.post(
      '/api/v1/funding/simulator/checkout/$publicReference',
      {'outcome': outcome},
    );
    return mapOrder(json);
  }

  /// Fetches the current status of an order (used after a lost response).
  Future<FundingOrder> fetchStatus(String publicReference) async {
    final json = await _client.get('/api/v1/funding/$publicReference/status');
    return mapOrder(json);
  }

  /// Reports the hosted-checkout success signature back to the server so it can
  /// record the payment immediately (the signed webhook remains authoritative
  /// for money received; the server decides VERIFIED vs PAYMENT_PENDING).
  Future<FundingOrder> verifyPayment({
    required String publicReference,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final json = await _client.post('/api/v1/funding/$publicReference/verify', {
      'orderId': orderId,
      'paymentId': paymentId,
      'signature': signature,
    });
    return mapOrder(json);
  }

  /// Fetches sanitized order history.
  Future<List<FundingOrder>> fetchHistory() async {
    final json = await _client.get('/api/v1/funding/history');
    final rawOrders = json['orders'] as List? ?? const [];
    return [
      for (final raw in rawOrders)
        if (raw is Map<String, dynamic>) mapOrder(raw),
    ];
  }
}

/// Safely converts a raw API map into a [FundingOrder].
FundingOrder mapOrder(Map<String, dynamic> json) {
  try {
    return FundingOrder.fromJson(json);
  } catch (_) {
    throw const FundingException(
      FundingFailureKind.malformedResponse,
      'The funding service returned an unexpected response.',
    );
  }
}
