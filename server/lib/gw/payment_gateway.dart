/// Payment-gateway abstraction.
///
/// The HTTP layer depends only on this interface. A real gateway adapter
/// (e.g. Razorpay) implements the same contract; the shipped build uses
/// [SimulatedGateway] so the entire production path — server-side order
/// creation, signed webhook, idempotency, verification — can run locally and
/// in tests without credentials.
library;

import 'dart:typed_data';

import '../domain/models.dart';

/// Result of creating an order at the gateway.
class GatewayCreateResult {
  final String gatewayOrderId;
  final Map<String, Object?> checkoutInfo;

  const GatewayCreateResult({
    required this.gatewayOrderId,
    required this.checkoutInfo,
  });
}

/// Outcome used by the simulated gateway to finalize a checkout.
enum SimulatedOutcome { success, failure, cancel }

/// A signed webhook payload as the gateway would deliver it.
class GatewayWebhookDelivery {
  /// Raw payload that must be verified against [headers].
  final Uint8List body;

  /// Gateway headers, including the signature header.
  final Map<String, String> headers;

  const GatewayWebhookDelivery({required this.body, required this.headers});
}

/// Raised when a webhook signature does not verify.
class GatewaySignatureException implements Exception {
  final String reason;

  const GatewaySignatureException(this.reason);

  @override
  String toString() => 'GatewaySignatureException: $reason';
}

/// Raised when a gateway operation fails for a non-security reason.
class GatewayOperationException implements Exception {
  final String code;
  final String message;

  const GatewayOperationException(this.code, this.message);

  @override
  String toString() => 'GatewayOperationException($code): $message';
}

/// Interface every payment gateway adapter must implement.
abstract class PaymentGateway {
  /// Human-readable transport identifier (e.g. 'simulated', 'razorpay').
  String get transportName;

  /// Name of the header carrying the webhook signature (e.g.
  /// 'X-Razorpay-Signature').
  String get signatureHeaderName;

  /// Public key identifier that may be handed to the client to open the
  /// checkout. Never a secret. Null for sandbox/simulated transports.
  String? get publicKeyId;

  /// Asks the gateway to register a new order. Amount/currency are taken from
  /// [order] (server-authoritative) — the gateway must charge exactly that.
  Future<GatewayCreateResult> createOrder(FundingOrder order);

  /// Returns details of whether the payment capture is missing, full, or no
  /// payment is on file, plus any gateway payment id.
  Future<GatewayLedgerEntry> fetchPayment(String gatewayOrderId);

  /// Verifies the signature included in the Checkout success callback that the
  /// mobile client submits for immediate confirmation. Throws
  /// [GatewaySignatureException] when the signature does not verify. Only the
  /// server holds the key needed to compute this signature.
  void verifyClientSignature({
    required FundingOrder order,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String signature,
  });

  /// Verifies [body] against [headers]. Returns the raw payload string when
  /// the signature checks out, otherwise throws [GatewaySignatureException].
  String verifyAndExtractPayload(Uint8List body, Map<String, String> headers);

  /// Parses a verified payload into a [SimulatedOutcome]-agnostic event.
  GatewayEvent parseEvent(String payload);
}

/// A normalized gateway payment event usable by the verification pipeline.
class GatewayEvent {
  final String gatewayEventId;
  final String eventType;
  final String gatewayOrderId;
  final String gatewayPaymentId;
  final int amountMinor;
  final String currency;

  const GatewayEvent({
    required this.gatewayEventId,
    required this.eventType,
    required this.gatewayOrderId,
    required this.gatewayPaymentId,
    required this.amountMinor,
    required this.currency,
  });

  bool get isSuccess =>
      eventType == 'order.captured' || eventType == 'order.paid';

  bool get isFailure => eventType == 'order.failed';

  bool get isCancellation => eventType == 'order.cancelled';
}

/// What the gateway currently knows about a single order's payment.
class GatewayLedgerEntry {
  final String gatewayOrderId;
  final String? gatewayPaymentId;
  final int amountMinor;
  final String currency;
  final String state; // matching PaymentStatus wire
  final bool hasPayment;

  const GatewayLedgerEntry({
    required this.gatewayOrderId,
    required this.gatewayPaymentId,
    required this.amountMinor,
    required this.currency,
    required this.state,
    required this.hasPayment,
  });
}
