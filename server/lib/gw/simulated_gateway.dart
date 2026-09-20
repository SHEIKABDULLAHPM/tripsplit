/// Simulated payment gateway.
///
/// Mirrors the behaviour of a hosted payment gateway so the whole funding
/// pipeline — order creation, checkout hand-off, signed webhook delivery,
/// duplicate-event suppression, verification — is exercised end-to-end without
/// real credentials. Sandbox-only; a live deployment replaces it with a real
/// adapter and never exposes the checkout-simulator route.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/models.dart';
import 'payment_gateway.dart';

const gatewayHeaderSignature = 'X-Gateway-Signature';

/// HMAC-SHA256-signed webhook simulation.
class SimulatedGateway implements PaymentGateway {
  final String webhookSecret;
  int _orderSequence = 0;
  int _paymentSequence = 0;

  final Map<String, _SimRecord> _records = {};

  /// When true, fetchPayment reports a mismatch for a subset of orders —
  /// used to demonstrate reconciliation detecting drift.
  final bool failReconciliationProbe;

  SimulatedGateway({
    required this.webhookSecret,
    this.failReconciliationProbe = false,
  });

  @override
  String get transportName => 'simulated';

  @override
  String get signatureHeaderName => gatewayHeaderSignature;

  @override
  String? get publicKeyId => null;

  // ------------------------------------------------------------- lifecycle

  @override
  Future<GatewayCreateResult> createOrder(FundingOrder order) async {
    if (_records.containsKey(order.publicReference)) {
      throw GatewayOperationException(
        'duplicate_order',
        'Order already registered at gateway',
      );
    }
    _orderSequence += 1;
    final gatewayOrderId = 'gwo_$_orderSequence';
    _records[order.publicReference] = _SimRecord(
      publicReference: order.publicReference,
      gatewayOrderId: gatewayOrderId,
      amountMinor: order.amountMinor,
      currency: order.currency,
      state: 'pending',
      paymentId: null,
    );
    return GatewayCreateResult(
      gatewayOrderId: gatewayOrderId,
      checkoutInfo: const {
        'mode': 'simulated',
        'method': 'explicit-checkout',
        'message': 'Sandbox checkout — no real money moves.',
      },
    );
  }

  @override
  Future<GatewayLedgerEntry> fetchPayment(String gatewayOrderId) async {
    final record = _byGatewayOrderId(gatewayOrderId);
    if (record == null) {
      return const GatewayLedgerEntry(
        gatewayOrderId: '',
        gatewayPaymentId: null,
        amountMinor: 0,
        currency: 'INR',
        state: 'none',
        hasPayment: false,
      );
    }
    if (failReconciliationProbe && record.state == 'pending') {
      // Simulate the gateway knowing a payment the ledger does not.
      return GatewayLedgerEntry(
        gatewayOrderId: record.gatewayOrderId,
        gatewayPaymentId: 'gw_probe_${record.gatewayOrderId}',
        amountMinor: record.amountMinor,
        currency: record.currency,
        state: 'captured',
        hasPayment: true,
      );
    }
    return GatewayLedgerEntry(
      gatewayOrderId: record.gatewayOrderId,
      gatewayPaymentId: record.paymentId,
      amountMinor: record.amountMinor,
      currency: record.currency,
      state: record.state,
      hasPayment: record.paymentId != null,
    );
  }

  /// Completes a checkout the way a real user would at the gateway. Produces
  /// a signed webhook payload that the server [SimulatedGateway.deliver]s
  /// through the exact same verification pipeline as production.
  GatewayWebhookDelivery completePayment({
    required String publicReference,
    required SimulatedOutcome outcome,
  }) {
    final record = _records[publicReference];
    if (record == null) {
      throw GatewayOperationException('unknown_order', 'No simulated order');
    }
    final eventType = switch (outcome) {
      SimulatedOutcome.success => 'order.captured',
      SimulatedOutcome.failure => 'order.failed',
      SimulatedOutcome.cancel => 'order.cancelled',
    };
    if (outcome == SimulatedOutcome.success) {
      _paymentSequence += 1;
      record.paymentId = 'gwp_${record.gatewayOrderId}_$_paymentSequence';
      record.state = 'captured';
    } else {
      record.state = outcome == SimulatedOutcome.failure
          ? 'failed'
          : 'cancelled';
    }
    final event = {
      'gatewayEventId': 'gwe_${record.gatewayOrderId}_${record.state}',
      'eventType': eventType,
      'gatewayOrderId': record.gatewayOrderId,
      'gatewayPaymentId': record.paymentId ?? 'gwp_none',
      'amountMinor': record.amountMinor,
      'currency': record.currency,
    };
    final body = utf8.encode(json.encode(event));
    final signature = _sign(body);
    return GatewayWebhookDelivery(
      body: Uint8List.fromList(body),
      headers: {gatewayHeaderSignature: signature},
    );
  }

  String _sign(List<int> body) {
    return Hmac(sha256, utf8.encode(webhookSecret)).convert(body).toString();
  }

  bool _verify(List<int> body, String expected) {
    final actual = Hmac(
      sha256,
      utf8.encode(webhookSecret),
    ).convert(body).toString();
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  @override
  void verifyClientSignature({
    required FundingOrder order,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String signature,
  }) {
    final expected = Hmac(
      sha256,
      utf8.encode(webhookSecret),
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

  _SimRecord? _byGatewayOrderId(String gatewayOrderId) {
    for (final record in _records.values) {
      if (record.gatewayOrderId == gatewayOrderId) return record;
    }
    return null;
  }

  @override
  String verifyAndExtractPayload(Uint8List body, Map<String, String> headers) {
    final provided = headers[gatewayHeaderSignature];
    if (provided == null || provided.isEmpty) {
      throw const GatewaySignatureException('missing signature');
    }
    if (!_verify(body, provided)) {
      throw const GatewaySignatureException('signature mismatch');
    }
    return utf8.decode(body);
  }

  @override
  GatewayEvent parseEvent(String payload) {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return GatewayEvent(
      gatewayEventId: json['gatewayEventId'] as String,
      eventType: json['eventType'] as String,
      gatewayOrderId: json['gatewayOrderId'] as String,
      gatewayPaymentId: json['gatewayPaymentId'] as String,
      amountMinor: json['amountMinor'] as int,
      currency: json['currency'] as String,
    );
  }
}

class _SimRecord {
  final String publicReference;
  final String gatewayOrderId;
  final int amountMinor;
  final String currency;
  String state;
  String? paymentId;

  _SimRecord({
    required this.publicReference,
    required this.gatewayOrderId,
    required this.amountMinor,
    required this.currency,
    required this.state,
    this.paymentId,
  });
}
