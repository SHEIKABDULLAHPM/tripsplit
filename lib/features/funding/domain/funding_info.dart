/// Funding domain types.
///
/// A funding order is the only online artifact TripSplit ever creates. It
/// lives entirely inside the funding feature and is never written to the
/// offline trip database.
///
/// IMPORTANT: the client-side enum below is purely a UI chooser and carries
/// only a *display* price. The server is the authority on the actual amount —
/// it validates the type and prices it in paise itself. No trip logic reads
/// these values.
library;

import 'dart:convert';

/// The two funding plans a user can choose from.
enum FundingType {
  support49(
    wire: 'SUPPORT_49',
    displayName: 'Support Funding',
    displayRupees: 49,
    purpose: 'Support the ongoing maintenance and development of TripSplit.',
  ),
  future199(
    wire: 'FUTURE_199',
    displayName: 'Future Funding',
    displayRupees: 199,
    purpose:
        'Support future development, infrastructure, and the continuing '
        'evolution of TripSplit.',
  );

  const FundingType({
    required this.wire,
    required this.displayName,
    required this.displayRupees,
    required this.purpose,
  });

  final String wire;
  final String displayName;

  /// Display-only price in whole rupees for the selection cards.
  final int displayRupees;
  final String purpose;

  static FundingType fromWire(String? value) => values.firstWhere(
    (type) => type.wire == value,
    orElse: () => values.first,
  );
}

/// Lifecycle of an order as reported by the server.
enum FundingStatus {
  created('CREATED'),
  checkoutStarted('CHECKOUT_STARTED'),
  paymentPending('PAYMENT_PENDING'),
  authorized('AUTHORIZED'),
  captured('CAPTURED'),
  verificationPending('VERIFICATION_PENDING'),
  verified('VERIFIED'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  expired('EXPIRED'),
  refunded('REFUNDED');

  const FundingStatus(this.wire);

  final String wire;

  static FundingStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wire == value,
    orElse: () => FundingStatus.created,
  );

  bool get isVerified => this == FundingStatus.verified;
  bool get isRefunded => this == FundingStatus.refunded;
  bool get isFailed => this == FundingStatus.failed;
  bool get isCancelled => this == FundingStatus.cancelled;

  /// Still in progress (not successful, not terminal-rejected).
  bool get isPending =>
      !isVerified &&
      !isRefunded &&
      !isFailed &&
      !isCancelled &&
      this != expired;
}

/// A funding order created on the server.
///
/// Amounts come from the server in minor units (paise) and are the only values
/// displayed as money after an order (and at checkout) — never [FundingType]
/// display price.
class FundingOrder {
  const FundingOrder({
    required this.publicReference,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.termsVersion,
    this.acceptedAt,
    this.createdAt,
    this.verifiedAt,
    this.note = '',
    this.checkoutMode = 'hosted',
    this.keyId,
    this.orderId,
  });

  factory FundingOrder.fromJson(Map<String, dynamic> json) {
    final checkout = json['checkout'];
    final checkoutMap = checkout is Map ? checkout : const <String, dynamic>{};
    final checkoutMode = checkoutMap['mode'] as String? ?? 'hosted';
    final isSimulated = checkoutMode != 'hosted';
    return FundingOrder(
      publicReference: json['publicReference'] as String,
      type: FundingType.fromWire(json['fundingType'] as String?),
      amountMinor: json['amountMinor'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      status: FundingStatus.fromWire(json['status'] as String?),
      termsVersion: json['termsVersion'] as String? ?? '',
      acceptedAt: json['acceptedAt'] as String?,
      createdAt: json['createdAt'] as String?,
      verifiedAt: json['verifiedAt'] as String?,
      note: isSimulated ? json['note'] as String? ?? '' : '',
      checkoutMode: checkoutMode,
      keyId: json['keyId'] as String? ?? checkoutMap['keyId'] as String?,
      orderId:
          json['orderId'] as String? ??
          checkoutMap['gatewayOrderId'] as String?,
    );
  }

  final String publicReference;
  final FundingType type;
  final int amountMinor;
  final String currency;
  final FundingStatus status;
  final String termsVersion;
  final String? acceptedAt;
  final String? createdAt;
  final String? verifiedAt;
  final String note;

  /// `simulated` (sandbox server) or `hosted` (real gateway). Controls whether
  /// the checkout UI uses the simulator or a hosted checkout.
  final String checkoutMode;

  /// Public gateway key id for the hosted checkout — never a secret. Null in
  /// sandbox/simulated mode.
  final String? keyId;

  /// Gateway order id to open the hosted checkout with. Null in sandbox mode.
  final String? orderId;

  /// True when the sandbox simulation route should be used to finalize the
  /// checkout (sandbox server only).
  bool get needsSimulatedCheckout => checkoutMode == 'simulated';

  /// True when a hosted (real-gateway) checkout can be launched for this
  /// order.
  bool get canLaunchHostedCheckout =>
      checkoutMode == 'hosted' &&
      (keyId?.isNotEmpty ?? false) &&
      (orderId?.isNotEmpty ?? false);

  @override
  String toString() => 'FundingOrder($publicReference, $status)';
}

/// A section of a funding document (terms, privacy, back).
class FundingDocumentSection {
  const FundingDocumentSection(this.heading, this.body);

  final String heading;
  final String body;
}

/// A versioned legal document displayed by the funding feature.
class FundingDocument {
  const FundingDocument({
    required this.name,
    required this.title,
    required this.sections,
    this.jurisdiction,
    this.effectiveVersion,
    this.draft = true,
  });

  factory FundingDocument.fromJson(Map<String, dynamic> json) =>
      FundingDocument(
        name: json['name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        jurisdiction: json['jurisdiction'] as String?,
        effectiveVersion: json['effectiveVersion'] as String?,
        draft: json['draft'] as bool? ?? true,
        sections: [
          for (final raw in json['sections'] as List? ?? const [])
            FundingDocumentSection(
              raw['heading'] as String? ?? '',
              raw['body'] as String? ?? '',
            ),
        ],
      );

  final String name;
  final String title;
  final String? jurisdiction;
  final String? effectiveVersion;
  final bool draft;
  final List<FundingDocumentSection> sections;
}

/// Parses a JSON response into a [FundingOrder], rejecting malformed bodies.
FundingOrder parseOrderJson(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FundingFormatException('Funding response was not an object.');
  }
  return FundingOrder.fromJson(decoded);
}

/// Raised when a funding payload from the server is structurally invalid.
class FundingFormatException implements Exception {
  const FundingFormatException(this.message);

  final String message;

  @override
  String toString() => 'FundingFormatException: $message';
}
