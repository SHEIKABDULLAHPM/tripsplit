/// Thin HTTP layer over [FundingService].
///
/// No business logic lives here. Routes map to service calls; errors map to
/// safe JSON responses. The only headers that are ever read are signature and
/// admin headers — webhook payloads are never logged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/legal_copy.dart';
import '../config/server_config.dart';
import '../db/funding_store.dart';
import '../domain/funding_type.dart';
import '../funding_service.dart';
import '../gw/payment_gateway.dart';
import '../gw/razorpay_gateway.dart';
import '../gw/simulated_gateway.dart';
import 'api_exception.dart';
import 'audit.dart';
import 'rate_limiter.dart';

/// Binds the funding HTTP API.
class FundingServer {
  final ServerConfig config;
  final FundingService service;
  final Audit audit;
  final RateLimiter _orders = RateLimiter(maxRequests: 10);
  final RateLimiter _webhooks = RateLimiter(maxRequests: 60);
  final RateLimiter _status = RateLimiter(maxRequests: 60);

  FundingServer({
    required this.config,
    required this.service,
    required this.audit,
  });

  /// Creates the runtime composition from [config].
  static FundingServer defaultInstance(ServerConfig config) {
    final audit = Audit();
    final store = FundingStore.open(config.dbPath);
    final PaymentGateway gateway;
    if (config.gatewayMode == 'razorpay') {
      gateway = RazorpayGateway(
        keyId: config.razorpayKeyId!,
        keySecret: config.razorpayKeySecret!,
        webhookSecret: config.webhookSecret,
        apiBase: config.razorpayApiBase,
      );
    } else {
      gateway = SimulatedGateway(webhookSecret: config.webhookSecret);
    }
    final service = FundingService(
      config: config,
      store: store,
      gateway: gateway,
      legal: LegalBundle.defaults(),
      audit: audit,
    );
    return FundingServer(config: config, service: service, audit: audit);
  }

  Future<HttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, config.port);
    server.listen(
      _dispatch,
      onError: (Object error, StackTrace stack) {
        audit.error('server_connection_error', {
          'type': error.runtimeType.toString(),
        });
      },
    );
    audit.info('server_started', {
      'port': config.port,
      'environment': config.environment,
      'gateway': service.gateway.transportName,
    });
    return server;
  }

  // ---------------------------------------------------------------- routing

  void _dispatch(HttpRequest request) {
    // Intentionally unawaited per-connection processing.
    unawaited(_handle(request));
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final method = request.method;
    final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final started = DateTime.now();

    try {
      HttpResponse? response = await _route(request, segments, method, ip);
      if (response == null) {
        response = request.response;
        await _sendJson(
          response,
          404,
          ApiErrors.notFound('Unknown endpoint.').toJson(),
        );
      }
    } on ApiException catch (e) {
      audit.warn('api_error', {
        'method': method,
        'path': path,
        'code': e.code,
        'detail': e.internalDetail ?? e.publicMessage,
      });
      await _sendJson(request.response, e.statusCode, e.toJson());
    } on GatewayOperationException catch (e) {
      audit.warn('gateway_error', {
        'method': method,
        'path': path,
        'code': e.code,
      });
      await _sendJson(
        request.response,
        503,
        ApiErrors.serviceUnavailable(
          'The payment service is temporarily unavailable. Please try again later.',
        ).toJson(),
      );
    } on HttpException catch (e) {
      await _sendJson(
        request.response,
        400,
        ApiErrors.badRequest('The request could not be read.').toJson(),
      );
      audit.warn('http_error', {
        'method': method,
        'path': path,
        'detail': e.message,
      });
    } catch (e) {
      audit.error('unhandled_server_error', {
        'method': method,
        'path': path,
        'type': e.runtimeType.toString(),
      });
      await _sendJson(
        request.response,
        500,
        ApiErrors.internal('An unexpected error occurred.').toJson(),
      );
    } finally {
      await request.response.close();
      final tookMs = DateTime.now().difference(started).inMilliseconds;
      audit.info('request_completed', {
        'method': method,
        'path': path,
        'ip': ip,
        'tookMs': tookMs,
      });
    }
  }

  Future<HttpResponse?> _route(
    HttpRequest request,
    List<String> segments,
    String method,
    String ip,
  ) async {
    if (segments.isEmpty) {
      return Future.value(null);
    }

    if (segments.length == 1 && segments[0] == 'health') {
      if (method != 'GET') return null;
      await _sendJson(request.response, 200, {
        'status': 'ok',
        'environment': config.environment,
        'gateway': service.gateway.transportName,
        'termsVersion': service.currentTermsVersion,
        'time': DateTime.now().toUtc().toIso8601String(),
      });
      return request.response;
    }

    // /api/v1/funding/...
    if (segments.length >= 3 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'funding') {
      final rest = segments.sublist(3);
      return _handleFunding(request, rest, method, ip);
    }

    return Future.value(null);
  }

  Future<HttpResponse?> _handleFunding(
    HttpRequest request,
    List<String> rest,
    String method,
    String ip,
  ) async {
    // POST /orders
    if (rest.length == 1 && rest[0] == 'orders') {
      if (method != 'POST') return null;
      if (!_orders.allow(ip)) {
        await _sendJson(
          request.response,
          429,
          ApiErrors.conflict(
            'rate_limited',
            'Too many requests. Try again shortly.',
          ).toJson(),
        );
        return request.response;
      }
      final body = await _readJsonBody(request);
      final typeWire = body['fundingType'] as String?;
      final termsVersion = body['termsVersion'] as String?;
      final accepted = body['accepted'] == true;
      final idem = body['idempotencyKey'] as String?;
      if (typeWire == null || termsVersion == null) {
        throw ApiErrors.badRequest(
          'fundingType and termsVersion are required.',
        );
      }
      final type = FundingType.fromWire(typeWire);
      if (type == null) {
        throw ApiErrors.badRequest('Unknown funding type.');
      }
      final created = await service.createOrder(
        fundingType: type,
        termsVersion: termsVersion,
        accepted: accepted,
        idempotencyKey: idem,
        clientIp: ip,
      );
      final order = created.order;
      final checkout = created.checkout;
      await _sendJson(request.response, 200, {
        'publicReference': order.publicReference,
        'orderId': order.gatewayOrderId,
        'keyId': service.gateway.publicKeyId,
        'fundingType': order.fundingType.wire,
        'displayName': order.fundingType.displayName,
        'purpose': order.fundingType.purpose,
        'amountMinor': order.amountMinor,
        'currency': order.currency,
        'status': order.status.wire,
        'termsVersion': order.termsVersion,
        'acceptedAt': order.acceptedAt,
        'createdAt': order.createdAt,
        'checkout': {
          'gatewayOrderId': checkout.gatewayOrderId,
          'mode': config.isSimulated ? 'simulated' : 'hosted',
          ...checkout.checkoutInfo,
          if (service.gateway.publicKeyId != null)
            'keyId': service.gateway.publicKeyId,
        },
        'note': config.isSimulated
            ? 'Sandbox mode — no real money moves.'
            : null,
      });
      return request.response;
    }

    // GET /terms[?version=]
    if (rest.length == 1 && rest[0] == 'terms') {
      if (method != 'GET') return null;
      final requested = request.uri.queryParameters['version'];
      final payload = service.termsPayload(requestedVersion: requested);
      await _sendJson(
        request.response,
        requested != null && payload['stale'] == true ? 422 : 200,
        payload,
      );
      return request.response;
    }

    // GET /history
    if (rest.length == 1 && rest[0] == 'history') {
      if (method != 'GET') return null;
      await _sendJson(request.response, 200, {'orders': service.history()});
      return request.response;
    }

    // GET /reconciliation (admin)
    if (rest.length == 1 && rest[0] == 'reconciliation') {
      if (method != 'GET') return null;
      _requireAdmin(request);
      final result = await service.reconcile();
      await _sendJson(request.response, 200, result);
      return request.response;
    }

    // POST /webhooks/<gateway>
    if (rest.length == 2 && rest[0] == 'webhooks') {
      if (method != 'POST') return null;
      if (!_webhooks.allow(ip)) {
        await _sendJson(
          request.response,
          429,
          ApiErrors.conflict(
            'rate_limited',
            'Too many webhook deliveries.',
          ).toJson(),
        );
        return request.response;
      }
      final body = await _readRawBody(request);
      // The signature header name is gateway-specific (Razorpay uses
      // 'X-Razorpay-Signature'); never assume the simulated header.
      final signatureHeader = service.gateway.signatureHeaderName;
      final signature = request.headers.value(signatureHeader);
      final headers = <String, String>{
        if (signature != null) signatureHeader: signature,
      };
      final result = service.processWebhook(body, headers);
      await _sendJson(request.response, 200, {
        'processed': result.processed,
        'idempotent': result.idempotent,
        'publicReference': result.publicReference,
        'status': result.orderStatus?.wire,
      });
      return request.response;
    }

    // POST /simulator/checkout/<reference>
    if (rest.length == 3 && rest[0] == 'simulator' && rest[1] == 'checkout') {
      if (method != 'POST') return null;
      if (!config.isSimulated) {
        throw ApiErrors.forbidden('Checkout simulation is disabled.');
      }
      if (!_orders.allow(ip)) {
        await _sendJson(
          request.response,
          429,
          ApiErrors.conflict(
            'rate_limited',
            'Too many requests. Try again shortly.',
          ).toJson(),
        );
        return request.response;
      }
      final reference = rest[2];
      final body = await _readJsonBody(request);
      final outcomeWire = body['outcome'] as String?;
      final outcome = switch (outcomeWire) {
        'success' => SimulatedOutcome.success,
        'failure' => SimulatedOutcome.failure,
        'cancel' => SimulatedOutcome.cancel,
        _ => throw ApiErrors.badRequest(
          'outcome must be success, failure, or cancel.',
        ),
      };
      final order = service.simulateCheckout(reference, outcome);
      await _sendJson(request.response, 200, {
        ...order.toJson(),
        'note': 'Sandbox simulation complete.',
      });
      return request.response;
    }

    // POST /<reference>/verify
    // Recovery leg: the mobile client returns the signature it received from
    // the gateway's Checkout success callback. Verification records the
    // payment (immediately VERIFIED when the gateway already confirms the
    // capture, otherwise PAYMENT_PENDING); the signed webhook remains the
    // authority for money being received.
    if (rest.length == 2 && rest[1] == 'verify') {
      if (method != 'POST') return null;
      if (!_status.allow(ip)) {
        await _sendJson(
          request.response,
          429,
          ApiErrors.conflict(
            'rate_limited',
            'Too many requests. Try again shortly.',
          ).toJson(),
        );
        return request.response;
      }
      final body = await _readJsonBody(request);
      final orderId = body['orderId'] as String?;
      final paymentId = body['paymentId'] as String?;
      final signature = body['signature'] as String?;
      if (orderId == null || paymentId == null || signature == null) {
        throw ApiErrors.badRequest(
          'orderId, paymentId and signature are required.',
        );
      }
      final order = await service.verifyClientPayment(
        publicReference: rest[0],
        gatewayOrderId: orderId,
        gatewayPaymentId: paymentId,
        signature: signature,
      );
      await _sendJson(request.response, 200, {
        ...order.toJson(),
        'orderId': order.gatewayOrderId,
      });
      return request.response;
    }

    // GET /<reference>/status
    if (rest.length == 2 && rest[1] == 'status' && method == 'GET') {
      if (!_status.allow(ip)) {
        await _sendJson(
          request.response,
          429,
          ApiErrors.conflict(
            'rate_limited',
            'Too many requests. Try again shortly.',
          ).toJson(),
        );
        return request.response;
      }
      final order = service.statusOf(rest[0]);
      await _sendJson(request.response, 200, order.toJson());
      return request.response;
    }

    return null;
  }

  // ------------------------------------------------------------- helpers

  void _requireAdmin(HttpRequest request) {
    final key = request.headers.value('X-Admin-Key');
    if (config.adminKey == null || key == null || key != config.adminKey) {
      throw ApiErrors.forbidden('Administrator access required.');
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final bytes = await _readRawBody(request);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, dynamic>) {
      throw ApiErrors.badRequest('Request body must be a JSON object.');
    }
    return decoded;
  }

  Future<Uint8List> _readRawBody(HttpRequest request) async {
    final chunks = <int>[];
    var total = 0;
    try {
      await for (final chunk in request) {
        total += chunk.length;
        if (total > config.maxBodyBytes) {
          throw ApiErrors.payloadTooLarge('Request body is too large.');
        }
        chunks.addAll(chunk);
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiErrors.badRequest('Request body could not be read.');
    }
    return Uint8List.fromList(chunks);
  }

  Future<void> _sendJson(HttpResponse response, int status, Object body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    if (config.environment == 'test') {
      response.headers.add('Access-Control-Allow-Origin', '*');
    }
    response.add(utf8.encode(json.encode(body)));
  }
}
