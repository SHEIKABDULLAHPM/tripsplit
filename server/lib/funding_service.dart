/// Funding service — orchestrates order creation, webhook verification, and
/// the isolated funding ledger. The HTTP layer is intentionally thin; every
/// business rule lives here.
///
/// Isolation guarantee: this service only ever touches its own SQLite funding
/// store and its own legal config. It imports nothing from the TripSplit
/// expense/trip domain and can never write to the offline trip database.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'config/legal_copy.dart';
import 'config/server_config.dart';
import 'db/funding_store.dart';
import 'domain/funding_status.dart';
import 'domain/funding_type.dart';
import 'domain/models.dart';
import 'gw/payment_gateway.dart';
import 'gw/simulated_gateway.dart';
import 'http/api_exception.dart';
import 'http/audit.dart';

/// Result of a processed webhook delivery.
class WebhookResult {
  final bool processed;
  final bool idempotent;
  final String? publicReference;
  final FundingStatus? orderStatus;

  const WebhookResult({
    required this.processed,
    required this.idempotent,
    this.publicReference,
    this.orderStatus,
  });
}

/// Orchestrates all funding operations.
class FundingService {
  final ServerConfig config;
  final FundingStore store;
  final PaymentGateway gateway;
  final LegalBundle legal;
  final Audit audit;
  final Random _random;

  FundingService({
    required this.config,
    required this.store,
    required this.gateway,
    required this.legal,
    required this.audit,
    Random? random,
  }) : _random = random ?? Random.secure();

  String get currentTermsVersion => legal.termsVersion;

  // ---------------------------------------------------------- order creation

  /// Creates a funding order. [termsVersion] must equal the server's current
  /// terms version and [accepted] must be true; the server is authoritative
  /// for both the amount and the terms accepted.
  Future<({FundingOrder order, GatewayCreateResult checkout})> createOrder({
    required FundingType fundingType,
    required String termsVersion,
    required bool accepted,
    required String? clientIp,
    String? idempotencyKey,
  }) async {
    if (!accepted) {
      throw ApiErrors.badRequest(
        'Terms must be accepted before funding.',
        detail: 'accepted=false',
      );
    }
    if (termsVersion != currentTermsVersion) {
      audit.warn('terms_version_rejected', {
        'termsVersion': termsVersion,
        'currentVersion': currentTermsVersion,
      });
      throw ApiErrors.unsupportedTerms(
        'This version of the terms is no longer current. Please review and '
        'accept the latest terms.',
      );
    }
    if (idempotencyKey != null && idempotencyKey.length > 200) {
      throw ApiErrors.badRequest('idempotencyKey is too long.');
    }

    final now = _now();
    final actualIdem = idempotencyKey ?? _generate('idem');
    final reference = _generate('TSPF');
    FundingOrder order;
    try {
      order = store.createOrder(
        publicReference: reference,
        fundingType: fundingType,
        termsVersion: termsVersion,
        acceptedAt: now,
        now: now,
        idempotencyKey: actualIdem,
        clientIp: clientIp,
      );
    } on IdempotencyConflict {
      // Lost a pairwise race: another request with the same idempotency key
      // created the order first. Replay the existing one rather than failing.
      final existing = store.findByIdempotencyKey(actualIdem);
      if (existing == null || existing.fundingType != fundingType) {
        throw ApiErrors.conflict(
          'idempotency_conflict',
          'This idempotency key was already used for a different funding type.',
        );
      }
      order = existing;
    }
    if (order.gatewayOrderId == null) {
      final checkout = await gateway.createOrder(order);
      store.transitionOrder(
        order.publicReference,
        to: FundingStatus.created,
        now: _now(),
        gatewayOrderId: checkout.gatewayOrderId,
      );
      audit.info('order_created', {
        'reference': order.publicReference,
        'type': fundingType.wire,
        'amountMinor': order.amountMinor,
        'currency': order.currency,
        'termsVersion': termsVersion,
        'gateway': gateway.transportName,
        'idempotentReplay': order.createdAt != now,
      });
      return (
        order: order.copyWith(gatewayOrderId: checkout.gatewayOrderId),
        checkout: checkout,
      );
    }
    return (
      order: order,
      checkout: const GatewayCreateResult(
        gatewayOrderId: 'replayed',
        checkoutInfo: {'mode': 'replayed'},
      ),
    );
  }

  // ---------------------------------------------------------------- status

  FundingOrder statusOf(String publicReference) {
    final order = store.findByReference(publicReference);
    if (order == null) {
      throw ApiErrors.notFound('No funding order for this reference.');
    }
    return order;
  }

  // ------------------------------------------------- client-side verification

  /// Recovery path for a hosted checkout: the mobile client returns the
  /// signature from the gateway's Checkout success callback so the server can
  /// record the payment without waiting for the webhook.
  ///
  /// Never declares money received on its own — the signed webhook remains the
  /// authority for VERIFIED. When the gateway already confirms the capture the
  /// order is verified immediately; otherwise it is recorded as pending
  /// (PAYMENT_PENDING) and the webhook advances it later.
  Future<FundingOrder> verifyClientPayment({
    required String publicReference,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String signature,
  }) async {
    final order = store.findByReference(publicReference);
    if (order == null) {
      throw ApiErrors.notFound('No funding order for this reference.');
    }
    if (order.status.isPaid) {
      return order; // verified or refunded — nothing to reconcile
    }
    if (order.gatewayOrderId == null ||
        order.gatewayOrderId != gatewayOrderId) {
      throw ApiErrors.badRequest(
        'The reported gateway order does not match the funding order.',
        detail: 'gateway order id mismatch',
      );
    }
    try {
      gateway.verifyClientSignature(
        order: order,
        gatewayOrderId: gatewayOrderId,
        gatewayPaymentId: gatewayPaymentId,
        signature: signature,
      );
    } on GatewaySignatureException catch (e) {
      audit.warn('checkout_signature_rejected', {
        'reference': publicReference,
        'reason': e.reason,
      });
      throw ApiErrors.unauthorized(
        'The checkout signature could not be verified.',
      );
    }

    final now = _now();

    // Ask the gateway what it knows about the payment. Unreachable gateways
    // are tolerated: a valid signature plus the later webhook reconciles the
    // order.
    GatewayLedgerEntry? gatewayEntry;
    try {
      gatewayEntry = await gateway.fetchPayment(gatewayOrderId);
    } catch (_) {
      audit.warn('checkout_fetch_rejected', {'reference': publicReference});
    }

    final captureConfirmed =
        gatewayEntry != null &&
        gatewayEntry.hasPayment &&
        gatewayEntry.state == 'captured' &&
        gatewayEntry.amountMinor == order.amountMinor &&
        gatewayEntry.currency == order.currency;
    if (captureConfirmed) {
      try {
        store.verifyPayment(
          gatewayOrderId: gatewayOrderId,
          gatewayPaymentId: gatewayPaymentId,
          amountMinor: order.amountMinor,
          currency: order.currency,
          now: now,
        );
      } on FundingStoreException catch (e) {
        // The ledger rejected the gateway-reported amount; leave the order for
        // the webhook and reconciliation to sort out rather than recording a
        // pending payment with mismatched amounts.
        audit.warn('checkout_store_rejected', {
          'reference': publicReference,
          'code': e.code,
        });
        return statusOf(publicReference);
      }
      audit.info('checkout_verified_immediately', {
        'reference': publicReference,
        'paymentId': gatewayPaymentId,
      });
      return statusOf(publicReference);
    }

    // No confirmed capture yet: record a pending payment so the order reflects
    // that money is expected, then let the webhook advance it to VERIFIED.
    final alreadyRecorded = store
        .listPaymentsForOrder(order.publicReference)
        .any(
          (p) =>
              p.gatewayPaymentId == gatewayPaymentId ||
              p.gatewayOrderId == gatewayOrderId,
        );
    if (gatewayPaymentId.isNotEmpty && !alreadyRecorded) {
      store.insertPayment(
        fundingOrderPublicRef: order.publicReference,
        gatewayPaymentId: gatewayPaymentId,
        gatewayOrderId: gatewayOrderId,
        amountMinor: order.amountMinor,
        currency: order.currency,
        status: PaymentStatus.pending,
        now: now,
      );
    }
    final updated = store.transitionOrder(
      order.publicReference,
      to: FundingStatus.paymentPending,
      now: now,
    );
    audit.info('checkout_payment_pending', {
      'reference': order.publicReference,
      'paymentId': gatewayPaymentId,
    });
    return updated ?? order;
  }

  // --------------------------------------------------------------- webhooks

  /// Verifies, deduplicates, and applies a gateway webhook. This is the only
  /// place where real money is recognized as received — the simulator routes
  /// through here too, keeping one verification path.
  WebhookResult processWebhook(Uint8List body, Map<String, String> headers) {
    final String payload;
    try {
      payload = gateway.verifyAndExtractPayload(body, headers);
    } on GatewaySignatureException catch (e) {
      audit.warn('webhook_signature_rejected', {'reason': e.reason});
      throw ApiErrors.unauthorized('Webhook signature could not be verified.');
    }

    final GatewayEvent event;
    try {
      event = gateway.parseEvent(payload);
    } catch (_) {
      throw ApiErrors.badRequest('Webhook payload could not be parsed.');
    }

    if (event.gatewayEventId.isEmpty ||
        event.gatewayOrderId.isEmpty ||
        event.gatewayPaymentId.isEmpty ||
        event.amountMinor <= 0 ||
        event.currency != 'INR') {
      throw ApiErrors.badRequest('Webhook event is malformed.');
    }

    final payloadHash = _sha256Hex(payload);
    final now = _now();

    if (store.isWebhookEventProcessed(event.gatewayEventId)) {
      audit.info('webhook_idempotent_replay', {
        'eventId': event.gatewayEventId,
        'orderRef': event.gatewayOrderId,
      });
      return const WebhookResult(processed: true, idempotent: true);
    }
    final inserted = store.recordWebhookEvent(
      gatewayEventId: event.gatewayEventId,
      eventType: event.eventType,
      gatewayPaymentId: event.gatewayPaymentId,
      payloadHash: payloadHash,
      now: now,
    );
    if (!inserted) {
      return const WebhookResult(processed: true, idempotent: true);
    }

    try {
      if (event.isSuccess) {
        final reference = store.verifyPayment(
          gatewayOrderId: event.gatewayOrderId,
          gatewayPaymentId: event.gatewayPaymentId,
          amountMinor: event.amountMinor,
          currency: event.currency,
          now: now,
        );
        store.markWebhookEventProcessed(event.gatewayEventId);
        audit.info('payment_verified', {
          'eventId': event.gatewayEventId,
          'reference': reference,
          'paymentId': event.gatewayPaymentId,
          'amountMinor': event.amountMinor,
        });
        return WebhookResult(
          processed: true,
          idempotent: false,
          publicReference: reference,
          orderStatus: FundingStatus.verified,
        );
      }
      if (event.isFailure) {
        final reference = store.failPayment(
          gatewayOrderId: event.gatewayOrderId,
          gatewayPaymentId: event.gatewayPaymentId,
          now: now,
        );
        store.markWebhookEventProcessed(event.gatewayEventId);
        audit.warn('payment_failed', {
          'eventId': event.gatewayEventId,
          'reference': reference,
          'paymentId': event.gatewayPaymentId,
        });
        return WebhookResult(
          processed: true,
          idempotent: false,
          publicReference: reference,
          orderStatus: FundingStatus.failed,
        );
      }
      if (event.isCancellation) {
        final order = store.findByGatewayOrderId(event.gatewayOrderId);
        if (order == null) {
          store.markWebhookEventProcessed(event.gatewayEventId);
          audit.info('webhook_cancel_unknown_order', {
            'eventId': event.gatewayEventId,
            'gatewayOrderId': event.gatewayOrderId,
          });
          return const WebhookResult(
            processed: true,
            idempotent: true,
          );
        }
        if (order.status.isPaid) {
          store.markWebhookEventProcessed(event.gatewayEventId);
          audit.info('webhook_cancel_ignored_paid', {
            'eventId': event.gatewayEventId,
            'reference': order.publicReference,
          });
          return WebhookResult(
            processed: true,
            idempotent: false,
            publicReference: order.publicReference,
            orderStatus: order.status,
          );
        }
        store.transitionOrder(
          order.publicReference,
          to: FundingStatus.cancelled,
          now: now,
        );
        store.markWebhookEventProcessed(event.gatewayEventId);
        audit.info('payment_cancelled', {
          'eventId': event.gatewayEventId,
          'reference': order.publicReference,
        });
        return WebhookResult(
          processed: true,
          idempotent: false,
          publicReference: order.publicReference,
          orderStatus: FundingStatus.cancelled,
        );
      }
      throw ApiErrors.badRequest(
        'Unhandled webhook event type: ${event.eventType}.',
      );
    } on FundingStoreException catch (e) {
      audit.warn('webhook_store_rejected', {
        'eventId': event.gatewayEventId,
        'code': e.code,
        'detail': e.message,
      });
      throw ApiErrors.conflict(
        e.code,
        'Webhook could not be applied.',
        detail: e.message,
      );
    } on IdempotencyConflict {
      store.markWebhookEventProcessed(event.gatewayEventId);
      throw ApiErrors.conflict('idempotency_conflict', 'Event rejected.');
    }
  }

  // ------------------------------------------------------------- simulator

  /// Drives the simulated gateway through a checkout the way a real user
  /// would, then delivers the resulting webhook through the standard pipeline.
  /// Enabled only when the server runs in simulated mode.
  FundingOrder simulateCheckout(
    String publicReference,
    SimulatedOutcome outcome,
  ) {
    if (!config.isSimulated) {
      throw ApiErrors.forbidden('Checkout simulation is disabled.');
    }
    if (gateway is! SimulatedGateway) {
      throw ApiErrors.forbidden('Checkout simulation is unavailable.');
    }
    final delivery = (gateway as SimulatedGateway).completePayment(
      publicReference: publicReference,
      outcome: outcome,
    );
    processWebhook(delivery.body, delivery.headers);
    // Note: an idempotent replay of the event resets the reference to null, so
    // always read the current state of the order we were asked to simulate.
    return statusOf(publicReference);
  }

  // --------------------------------------------------------------- history

  /// Sanitized order history — no gateway payment ids, no signatures.
  List<Map<String, Object?>> history() {
    return [for (final order in store.listOrders()) order.toJson()];
  }

  // ----------------------------------------------------------------- terms

  Map<String, Object?> termsPayload({String? requestedVersion}) {
    if (requestedVersion != null && requestedVersion != currentTermsVersion) {
      return {'currentVersion': currentTermsVersion, 'stale': true};
    }
    return {
      'version': currentTermsVersion,
      'documents': [
        for (final doc in legal.documents)
          {
            'name': doc.name,
            'title': doc.title,
            'jurisdiction': doc.jurisdiction,
            'effectiveVersion': doc.effectiveVersion,
            'draft': doc.draft,
            'sections': [
              for (final s in doc.sections)
                {'heading': s.heading, 'body': s.body},
            ],
          },
      ],
    };
  }

  // -------------------------------------------------------- reconciliation

  /// Compares the local ledger with what the gateway reports for every order.
  Future<Map<String, Object?>> reconcile() async {
    final startedAt = _now();
    final mismatches = <Map<String, Object?>>[];
    for (final entry in store.allOrdersWithPayments()) {
      final order = entry.order;
      final gatewayOrderId = order.gatewayOrderId;
      if (gatewayOrderId == null) continue;
      GatewayLedgerEntry gatewayEntry;
      try {
        gatewayEntry = await gateway.fetchPayment(gatewayOrderId);
      } catch (_) {
        gatewayEntry = const GatewayLedgerEntry(
          gatewayOrderId: '',
          gatewayPaymentId: null,
          amountMinor: 0,
          currency: 'INR',
          state: 'unreachable',
          hasPayment: false,
        );
      }
      final localVerified = order.status == FundingStatus.verified;
      if (gatewayEntry.hasPayment && !localVerified) {
        mismatches.add({
          'reference': order.publicReference,
          'issue': 'gateway_has_payment_local_not_verified',
          'gatewayState': gatewayEntry.state,
        });
      } else if (!gatewayEntry.hasPayment && localVerified) {
        mismatches.add({
          'reference': order.publicReference,
          'issue': 'local_verified_gateway_has_none',
        });
      } else if (localVerified && gatewayEntry.state != 'captured') {
        mismatches.add({
          'reference': order.publicReference,
          'issue': 'status_drift',
          'gatewayState': gatewayEntry.state,
        });
      } else if (gatewayEntry.amountMinor != 0 &&
          (gatewayEntry.amountMinor != order.amountMinor ||
              gatewayEntry.currency != order.currency)) {
        mismatches.add({
          'reference': order.publicReference,
          'issue': 'amount_currency_mismatch',
          'gatewayAmountMinor': gatewayEntry.amountMinor,
          'orderAmountMinor': order.amountMinor,
        });
      }
    }
    store.recordReconciliationRun(
      startedAt: startedAt,
      finishedAt: _now(),
      mismatches: mismatches.length,
      detail: json.encode({'mismatches': mismatches}),
    );
    audit.info('reconciliation_completed', {'mismatches': mismatches.length});
    return {
      'ranAt': startedAt,
      'mismatchCount': mismatches.length,
      'mismatches': mismatches,
    };
  }

  // ----------------------------------------------------------------- utils

  String _generate(String prefix) {
    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final buffer = StringBuffer(prefix)..write('_');
    for (var i = 0; i < 14; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
