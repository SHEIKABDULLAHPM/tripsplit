/// Plain data models that travel between the database, the gateway, and the
/// HTTP layer.
library;

import 'funding_status.dart';
import 'funding_type.dart';

/// A funding order created on the server.
class FundingOrder {
  final String publicReference;
  final FundingType fundingType;
  final int amountMinor;
  final String currency;
  final FundingStatus status;
  final String termsVersion;
  final String? clientIp;
  final String createdAt;
  final String? acceptedAt;
  final String? gatewayOrderId;
  final String? idempotencyKey;
  final String? updatedAt;
  final String? verifiedAt;

  const FundingOrder({
    required this.publicReference,
    required this.fundingType,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.termsVersion,
    required this.createdAt,
    required this.idempotencyKey,
    this.clientIp,
    this.acceptedAt,
    this.gatewayOrderId,
    this.updatedAt,
    this.verifiedAt,
  });

  FundingOrder copyWith({
    FundingStatus? status,
    String? gatewayOrderId,
    String? verifiedAt,
    String? updatedAt,
  }) => FundingOrder(
    publicReference: publicReference,
    fundingType: fundingType,
    amountMinor: amountMinor,
    currency: currency,
    status: status ?? this.status,
    termsVersion: termsVersion,
    clientIp: clientIp,
    createdAt: createdAt,
    acceptedAt: acceptedAt,
    gatewayOrderId: gatewayOrderId ?? this.gatewayOrderId,
    idempotencyKey: idempotencyKey,
    updatedAt: updatedAt ?? this.updatedAt,
    verifiedAt: verifiedAt ?? this.verifiedAt,
  );

  Map<String, Object?> toJson() => {
    'publicReference': publicReference,
    'fundingType': fundingType.wire,
    'amountMinor': amountMinor,
    'currency': currency,
    'status': status.wire,
    'termsVersion': termsVersion,
    'acceptedAt': acceptedAt,
    'createdAt': createdAt,
    'verifiedAt': verifiedAt,
  };
}

/// A payment record captured from a gateway event.
class FundingPayment {
  final int id;
  final String fundingOrderPublicRef;
  final String gatewayPaymentId;
  final String gatewayOrderId;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;
  final String createdAt;
  final String? verifiedAt;

  const FundingPayment({
    required this.id,
    required this.fundingOrderPublicRef,
    required this.gatewayPaymentId,
    required this.gatewayOrderId,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
  });
}

/// A raw webhook event persisted for deduplication and audit.
class FundingWebhookEvent {
  final String gatewayEventId;
  final String eventType;
  final String gatewayPaymentId;
  final String payloadHash;
  final bool processed;
  final String createdAt;

  const FundingWebhookEvent({
    required this.gatewayEventId,
    required this.eventType,
    required this.gatewayPaymentId,
    required this.payloadHash,
    required this.processed,
    required this.createdAt,
  });
}
