/// Razorpay payment-gateway adapter.
///
/// Connects the funding server to Razorpay's Orders API and webhooks:
///  - orders are created server-side (amount/currency are the server's), so
///    the Secret never reaches the app — the client only ever receives the
///    public Key Id, the Order Id, the amount, and the currency;
///  - webhook payloads are verified with the Razorpay webhook secret via an
///    HMAC-SHA256 signature over the raw body (`X-Razorpay-Signature`);
///  - the Checkout success signature reported back to the app
///    (`order_id|payment_id` HMAC with the Key Secret) is verified here too.
///
/// No card, UPI, OTP, or CVV data is ever seen or stored.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'payment_gateway.dart';

/// Header carrying the Razorpay webhook signature.
const razorpayWebhookSignatureHeader = 'X-Razorpay-Signature';

/// Raised when the Razorpay API returns an unexpected/erroneous response.
class RazorpayApiException implements Exception {
  final String message;

  const RazorpayApiException(this.message);

  @override
  String toString() => 'RazorpayApiException: $message';
}

/// Razorpay adapter implementing [PaymentGateway].
class RazorpayGateway implements PaymentGateway {
  final String keyId;
  final String keySecret;
  final String webhookSecret;
  final String apiBase;
  final http.Client _client;

  RazorpayGateway({
    required this.keyId,
    required this.keySecret,
    required this.webhookSecret,
    http.Client? client,
    String apiBase = 'https://api.razorpay.com',
  }) : apiBase = _trimTrailingSlash(apiBase),
       _client = client ?? http.Client();

  static String _trimTrailingSlash(String value) {
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  @override
  String get transportName => 'razorpay';

  @override
  String get signatureHeaderName => razorpayWebhookSignatureHeader;

  @override
  String? get publicKeyId => keyId;

  String get _basicAuth {
    final credentials = base64Encode(utf8.encode('$keyId:$keySecret'));
    return 'Basic $credentials';
  }

  Map<String, String> get _authHeaders => {
    'Authorization': _basicAuth,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  // ------------------------------------------------------------- lifecycle

  @override
  Future<GatewayCreateResult> createOrder(FundingOrder order) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$apiBase/v1/orders'),
            headers: _authHeaders,
            body: jsonEncode({
              'amount': order.amountMinor,
              'currency': order.currency,
              'receipt': order.publicReference,
              'payment_capture': 1,
              'notes': {
                'fundingType': order.fundingType.wire,
                'publicReference': order.publicReference,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on RazorpayApiException {
      rethrow;
    } catch (e) {
      throw GatewayOperationException(
        'razorpay_unreachable',
        'Razorpay could not be reached (${e.runtimeType}).',
      );
    }
    final body = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final description = _razorpayError(body);
      throw GatewayOperationException(
        'razorpay_order_failed',
        'Razorpay rejected the order: $description',
      );
    }
    final gatewayOrderId = body['id'] as String?;
    if (gatewayOrderId == null || gatewayOrderId.isEmpty) {
      throw GatewayOperationException(
        'razorpay_order_failed',
        'Razorpay returned an order without an id.',
      );
    }
    return GatewayCreateResult(
      gatewayOrderId: gatewayOrderId,
      checkoutInfo: {'mode': 'hosted', 'keyId': keyId},
    );
  }

  @override
  Future<GatewayLedgerEntry> fetchPayment(String gatewayOrderId) async {
    http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$apiBase/v1/orders/$gatewayOrderId/payments'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw GatewayOperationException(
        'razorpay_unreachable',
        'Razorpay could not be reached.',
      );
    }
    final body = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GatewayOperationException(
        'razorpay_fetch_failed',
        'Razorpay could not fetch the order: ${_razorpayError(body)}',
      );
    }
    final items = body['items'] as List? ?? const [];
    if (items.isEmpty) {
      return GatewayLedgerEntry(
        gatewayOrderId: gatewayOrderId,
        gatewayPaymentId: null,
        amountMinor: 0,
        currency: 'INR',
        state: 'none',
        hasPayment: false,
      );
    }
    final first = items.first;
    if (first is! Map<String, dynamic>) {
      throw GatewayOperationException(
        'razorpay_fetch_failed',
        'Razorpay returned a malformed payments list.',
      );
    }
    final paymentId = first['id'] as String? ?? '';
    final amountMinor = first['amount'] as int? ?? 0;
    final currency = first['currency'] as String? ?? 'INR';
    final status = _normalizePaymentState(first['status'] as String?);
    return GatewayLedgerEntry(
      gatewayOrderId: gatewayOrderId,
      gatewayPaymentId: paymentId,
      amountMinor: amountMinor,
      currency: currency,
      state: status,
      hasPayment: paymentId.isNotEmpty,
    );
  }

  // -------------------------------------------------------- client callback

  @override
  void verifyClientSignature({
    required FundingOrder order,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String signature,
  }) {
    final expected = Hmac(
      sha256,
      utf8.encode(keySecret),
    ).convert(utf8.encode('$gatewayOrderId|$gatewayPaymentId')).toString();
    if (expected.length != signature.length) {
      throw const GatewaySignatureException('signature mismatch');
    }
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ signature.codeUnitAt(i);
    }
    if (diff != 0) {
      throw const GatewaySignatureException('signature mismatch');
    }
  }

  // --------------------------------------------------------------- webhooks

  @override
  String verifyAndExtractPayload(Uint8List body, Map<String, String> headers) {
    final provided = headers[razorpayWebhookSignatureHeader];
    if (provided == null || provided.isEmpty) {
      throw const GatewaySignatureException('missing signature');
    }
    final expected = Hmac(
      sha256,
      utf8.encode(webhookSecret),
    ).convert(body).toString();
    if (expected.length != provided.length) {
      throw const GatewaySignatureException('signature mismatch');
    }
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ provided.codeUnitAt(i);
    }
    if (diff != 0) {
      throw const GatewaySignatureException('signature mismatch');
    }
    return utf8.decode(body);
  }

  @override
  GatewayEvent parseEvent(String payload) {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      root = decoded;
    } catch (_) {
      throw const FormatException('malformed event payload');
    }

    final event = root['event'] as String? ?? '';
    final payloadSection = root['payload'];
    final eventType = switch (event) {
      'payment.captured' || 'order.paid' => 'order.captured',
      'payment.failed' => 'order.failed',
      'order.cancelled' => 'order.cancelled',
      _ => throw FormatException('unsupported razorpay event: $event'),
    };

    final Map<String, dynamic> orderEntity;
    final Map<String, dynamic>? paymentEntity;
    try {
      final orderSection = _entitySection(payloadSection, 'order');
      orderEntity = orderSection;
      paymentEntity = _entitySectionNullable(payloadSection, 'payment');
    } catch (_) {
      throw const FormatException('event payload is malformed');
    }

    final gatewayOrderId =
        paymentEntity?['order_id'] as String? ??
        orderEntity['id'] as String? ??
        '';
    final gatewayPaymentId =
        paymentEntity?['id'] as String? ?? '${gatewayOrderId}_$event';
    final amountMinor =
        paymentEntity?['amount'] as int? ?? orderEntity['amount'] as int? ?? 0;
    final currency =
        paymentEntity?['currency'] as String? ??
        orderEntity['currency'] as String? ??
        'INR';

    // Razorpay does not emit a stable event id; the payment id plus the event
    // name is globally unique per delivery and survives retries unchanged.
    final gatewayEventId = '$gatewayPaymentId:$event';

    return GatewayEvent(
      gatewayEventId: gatewayEventId,
      eventType: eventType,
      gatewayOrderId: gatewayOrderId,
      gatewayPaymentId: gatewayPaymentId,
      amountMinor: amountMinor,
      currency: currency,
    );
  }

  // ---------------------------------------------------------------- helpers

  Map<String, dynamic> _entitySection(Object? payload, String name) {
    final entity = _entitySectionNullable(payload, name);
    if (entity == null) {
      throw FormatException('missing $name entity');
    }
    return entity;
  }

  Map<String, dynamic>? _entitySectionNullable(Object? payload, String name) {
    if (payload is! Map<String, dynamic>) return null;
    final section = payload[name];
    if (section is! Map<String, dynamic>) return null;
    final entity = section['entity'];
    if (entity is! Map<String, dynamic>) return null;
    return entity;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _razorpayError(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final description = error['description'];
      if (description is String && description.isNotEmpty) return description;
    }
    return 'HTTP ${body['statusCode'] ?? 'unknown'}';
  }

  /// Maps a Razorpay payment `status` to the internal payment state wire.
  String _normalizePaymentState(String? status) => switch (status) {
    'captured' => 'captured',
    'authorized' => 'authorized',
    'failed' => 'failed',
    'refunded' => 'refunded',
    _ => 'pending',
  };
}
