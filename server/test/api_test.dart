import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tripsplit_funding_server/config/legal_copy.dart';
import 'package:tripsplit_funding_server/config/server_config.dart';
import 'package:tripsplit_funding_server/db/funding_store.dart';
import 'package:tripsplit_funding_server/domain/funding_status.dart';
import 'package:tripsplit_funding_server/funding_service.dart';
import 'package:tripsplit_funding_server/gw/simulated_gateway.dart';
import 'package:tripsplit_funding_server/http/audit.dart';
import 'package:tripsplit_funding_server/http/funding_server.dart';

const _terms = '2026-09-21';
const _secret = 'test-webhook-secret';

class TestContext {
  late FundingStore store;
  late SimulatedGateway gateway;
  late FundingService service;
  late FundingServer server;
  late HttpServer httpServer;
  late String baseUrl;

  Future<void> start({
    String gatewayMode = 'simulated',
    bool failReconciliationProbe = false,
  }) async {
    final config = ServerConfig(
      port: 0,
      dbPath: '',
      environment: 'test',
      gatewayMode: gatewayMode,
      webhookSecret: _secret,
      razorpayKeyId: null,
      razorpayKeySecret: null,
      razorpayApiBase: 'https://api.razorpay.com',
      adminKey: 'admin-key',
      currentTermsVersion: _terms,
      publicBaseUrl: 'http://127.0.0.1:0',
      maxBodyBytes: 1 << 20,
      createdAt: 0,
    );
    store = FundingStore.openInMemory();
    gateway = SimulatedGateway(
      webhookSecret: _secret,
      failReconciliationProbe: failReconciliationProbe,
    );
    final audit = Audit(sink: (_) {});
    service = FundingService(
      config: config,
      store: store,
      gateway: gateway,
      legal: LegalBundle.defaults(),
      audit: audit,
      random: Random(7),
    );
    server = FundingServer(config: config, service: service, audit: audit);
    httpServer = await server.start();
    baseUrl = 'http://127.0.0.1:${httpServer.port}';
  }

  Future<void> stop() async {
    await httpServer.close(force: true);
    store.close();
  }
}

Future<(int, Map<String, dynamic>)> _send(
  String method,
  String url, {
  Object? body,
  Map<String, String> headers = const {},
}) async {
  final uri = Uri.parse(url);
  final request = http.Request(method, uri);
  if (body != null) {
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  request.headers.addAll(headers);
  final streamed = await request.send();
  final response = await http.Response.fromStream(streamed);
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  return (response.statusCode, decoded as Map<String, dynamic>);
}

Future<(int, Map<String, dynamic>)> _post(
  String url,
  Object body, {
  Map<String, String> headers = const {},
}) => _send('POST', url, body: body, headers: headers);

Future<(int, Map<String, dynamic>)> _get(
  String url, {
  Map<String, String> headers = const {},
}) => _send('GET', url, headers: headers);

Future<Map<String, dynamic>> _createOrder(
  TestContext ctx, {
  String type = 'SUPPORT_49',
  String? idem,
  String terms = _terms,
  bool accepted = true,
  Object? extraBody,
}) async {
  final body = <String, Object?>{
    'fundingType': type,
    'termsVersion': terms,
    'accepted': accepted,
    if (idem != null) 'idempotencyKey': idem,
    if (extraBody != null) ...(extraBody as Map),
  };
  final (status, json) = await _post(
    '${ctx.baseUrl}/api/v1/funding/orders',
    body,
  );
  return {'status': status, 'json': json};
}

Future<(int, Map<String, dynamic>)> _complete(
  TestContext ctx,
  String ref,
  String outcome,
) => _post('${ctx.baseUrl}/api/v1/funding/simulator/checkout/$ref', {
  'outcome': outcome,
});

Future<(int, Map<String, dynamic>)> _status(TestContext ctx, String ref) =>
    _get('${ctx.baseUrl}/api/v1/funding/$ref/status');

void main() {
  late TestContext ctx;

  setUp(() async {
    ctx = TestContext();
    await ctx.start();
  });

  tearDown(() async {
    await ctx.stop();
  });

  group('create order', () {
    test('health endpoint', () async {
      final (status, json) = await _get('${ctx.baseUrl}/health');
      expect(status, 200);
      expect(json['status'], 'ok');
      expect(json['termsVersion'], _terms);
    });

    test('SUPPORT_49 returns authoritative ₹19 (1900 paise, INR)', () async {
      final res = await _createOrder(ctx);
      expect(res['status'], 200);
      final json = res['json'] as Map<String, dynamic>;
      expect(json['fundingType'], 'SUPPORT_49');
      expect(json['amountMinor'], 1900);
      expect(json['currency'], 'INR');
      expect(json['status'], 'CREATED');
      expect(json['termsVersion'], _terms);
      expect(json['acceptedAt'], isNotNull);
      expect((json['checkout'] as Map)['gatewayOrderId'], isNotNull);
      // The hosted checkout only needs the public key id; the top-level
      // orderId mirrors the gateway order for the client.
      expect(json['orderId'], (json['checkout'] as Map)['gatewayOrderId']);
      expect(json['keyId'], isNull); // simulated gateway exposes no key
    });

    test('FUTURE_199 returns authoritative ₹49 (4900 paise, INR)', () async {
      final res = await _createOrder(ctx, type: 'FUTURE_199');
      expect(res['status'], 200);
      final json = res['json'] as Map<String, dynamic>;
      expect(json['amountMinor'], 4900);
      expect(json['currency'], 'INR');
    });

    test('client-supplied amount is ignored (server authoritative)', () async {
      final res = await _createOrder(
        ctx,
        extraBody: {'amountMinor': 1, 'currency': 'USD'},
      );
      expect(res['status'], 200);
      final json = res['json'] as Map<String, dynamic>;
      expect(json['amountMinor'], 1900);
      expect(json['currency'], 'INR');
    });

    test('unknown funding type is rejected', () async {
      final res = await _createOrder(ctx, type: 'PLAN_999');
      expect(res['status'], 400);
    });

    test('terms acceptance required', () async {
      final res = await _createOrder(ctx, accepted: false);
      expect(res['status'], 400);
      expect((res['json'] as Map)['error']['code'], 'invalid_request');
    });

    test('stale terms version rejected', () async {
      final res = await _createOrder(ctx, terms: '2020-01-01');
      expect(res['status'], 422);
      expect(
        (res['json'] as Map)['error']['code'],
        'unsupported_terms_version',
      );
    });

    test('missing terms version rejected', () async {
      final (status, json) = await _post(
        '${ctx.baseUrl}/api/v1/funding/orders',
        {'fundingType': 'SUPPORT_49', 'accepted': true},
      );
      expect(status, 400);
      expect(
        json['error']['message'],
        contains('fundingType and termsVersion'),
      );
    });

    test('GET on /orders is not a route', () async {
      final (status, _) = await _get('${ctx.baseUrl}/api/v1/funding/orders');
      expect(status, 404);
    });
  });

  group('idempotency', () {
    test('sequential double-tap returns the same order once', () async {
      final a = await _createOrder(ctx, idem: 'dup-1');
      final b = await _createOrder(ctx, idem: 'dup-1');
      expect(a['status'], 200);
      expect(b['status'], 200);
      expect(
        (a['json'] as Map)['publicReference'],
        (b['json'] as Map)['publicReference'],
      );
      expect(ctx.store.listOrders().length, 1);
    });

    test('concurrent double-tap creates exactly one order', () async {
      final results = await Future.wait([
        for (final _ in List.filled(2, 0)) _createOrder(ctx, idem: 'dup-c'),
      ]);
      for (final r in results) {
        expect(r['status'], 200);
      }
      // The reference must be shared across both responses.
      expect(
        ((results[0]['json'] as Map)['publicReference']),
        ((results[1]['json'] as Map)['publicReference']),
      );
      expect(ctx.store.listOrders().length, 1);
    });

    test('same key with different funding type is a conflict', () async {
      await _createOrder(ctx, type: 'SUPPORT_49', idem: 'key-x');
      final b = await _createOrder(ctx, type: 'FUTURE_199', idem: 'key-x');
      expect(b['status'], 409);
      expect((b['json'] as Map)['error']['code'], 'idempotency_conflict');
    });

    test('two orders without a key are distinct', () async {
      final a = await _createOrder(ctx);
      final b = await _createOrder(ctx);
      expect(
        (a['json'] as Map)['publicReference'],
        isNot((b['json'] as Map)['publicReference']),
      );
    });
  });

  group('payment lifecycle', () {
    test('order is CREATED before any payment', () async {
      final res = await _createOrder(ctx);
      final json = res['json'] as Map<String, dynamic>;
      expect(json['status'], 'CREATED');
      final (s, actual) = await _status(ctx, json['publicReference'] as String);
      expect(s, 200);
      expect(actual['status'], 'CREATED');
    });

    test(
      'successful simulated checkout ends VERIFIED with a receipt',
      () async {
        final res = await _createOrder(ctx, idem: 'pay-s');
        final ref = (res['json'] as Map)['publicReference'] as String;
        final (status, json) = await _complete(ctx, ref, 'success');
        expect(status, 200);
        expect(json['status'], 'VERIFIED');
        expect(json['verifiedAt'], isNotNull);

        // Status reflects the paid order and exposes no gateway secrets.
        final (s, st) = await _status(ctx, ref);
        expect(s, 200);
        expect(st['status'], 'VERIFIED');
        expect(st.containsKey('gatewayOrderId'), isFalse);
        expect(st.containsKey('gatewayPaymentId'), isFalse);

        final payments = ctx.store.listPaymentsForOrder(ref);
        expect(payments.length, 1);
        expect(payments.single.status.name, 'verified');
      },
    );

    test('failed checkout ends FAILED', () async {
      final res = await _createOrder(ctx, idem: 'pay-f');
      final ref = (res['json'] as Map)['publicReference'] as String;
      final (status, json) = await _complete(ctx, ref, 'failure');
      expect(status, 200);
      expect(json['status'], 'FAILED');
      final (s, _) = await _status(ctx, ref);
      expect(s, 200);
    });

    test('cancelled checkout ends CANCELLED', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final (status, _) = await _complete(ctx, ref, 'cancel');
      expect(status, 200);
      final (s, st) = await _status(ctx, ref);
      expect(st['status'], 'CANCELLED');
    });

    test('network-lost after payment: client recovers via status', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      // Payment goes through on the server; the client never sees the response.
      final (status, _) = await _complete(ctx, ref, 'success');
      expect(status, 200);
      final (s, st) = await _status(ctx, ref);
      expect(st['status'], 'VERIFIED');
    });

    test('duplicate webhook delivery is idempotent', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      await _complete(ctx, ref, 'success');
      // Re-deliver the same event (same outcome → same event id).
      final (status, json) = await _complete(ctx, ref, 'success');
      expect(status, 200);
      expect(json['status'], 'VERIFIED');
      expect(ctx.store.listPaymentsForOrder(ref).length, 1);
    });

    test('unknown order status is 404', () async {
      final (status, _) = await _status(ctx, 'TSPF_nonexistent');
      expect(status, 404);
    });
  });

  group('webhook security', () {
    Future<(int, Map<String, dynamic>)> _deliverWebhook(
      Map<String, dynamic> event, {
      String? secret,
    }) async {
      final payload = jsonEncode(event);
      final sig = Hmac(
        sha256,
        utf8.encode(secret ?? _secret),
      ).convert(utf8.encode(payload)).toString();
      final request = http.Request(
        'POST',
        Uri.parse('${ctx.baseUrl}/api/v1/funding/webhooks/payment-gateway'),
      );
      request.headers['X-Gateway-Signature'] = sig;
      request.body = payload;
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return (response.statusCode, decoded as Map<String, dynamic>);
    }

    test('missing signature is rejected', () async {
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/webhooks/payment-gateway',
        {'eventType': 'order.captured'},
      );
      expect(status, 401);
    });

    test('wrong signature is rejected', () async {
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/webhooks/payment-gateway',
        {},
        headers: {'X-Gateway-Signature': '0123456789abcdef'},
      );
      expect(status, 401);
    });

    test('tampered body (signed with the wrong key) is rejected', () async {
      final res = await _createOrder(ctx);
      final gwo = (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
      final (status, _) = await _deliverWebhook({
        'gatewayEventId': 'e1',
        'eventType': 'order.captured',
        'gatewayOrderId': gwo,
        'gatewayPaymentId': 'pay_bad',
        'amountMinor': 1900,
        'currency': 'INR',
      }, secret: 'attacker-secret');
      expect(status, 401);
    });

    test('wrong amount can never mark an order verified', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final gwo = (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
      final (status, json) = await _deliverWebhook({
        'gatewayEventId': 'e-amt',
        'eventType': 'order.captured',
        'gatewayOrderId': gwo,
        'gatewayPaymentId': 'pay_amt',
        'amountMinor': 1, // wrong
        'currency': 'INR',
      });
      expect(status, 409);
      expect(json['error']['code'], 'amount_mismatch');
      final (_, st) = await _status(ctx, ref);
      expect(st['status'], 'CREATED');
      expect(ctx.store.listPaymentsForOrder(ref), isEmpty);
    });

    test('wrong currency event is malformed and rejected', () async {
      final res = await _createOrder(ctx);
      final gwo = (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
      final (status, json) = await _deliverWebhook({
        'gatewayEventId': 'e-cur',
        'eventType': 'order.captured',
        'gatewayOrderId': gwo,
        'gatewayPaymentId': 'pay_cur',
        'amountMinor': 1900,
        'currency': 'USD',
      });
      expect(status, 400);
      expect(json['error']['code'], 'invalid_request');
      final (_, st) = await _status(
        ctx,
        (res['json'] as Map)['publicReference'] as String,
      );
      expect(st['status'], 'CREATED');
    });

    test('unknown gateway order is rejected', () async {
      final (status, json) = await _deliverWebhook({
        'gatewayEventId': 'e-unk',
        'eventType': 'order.captured',
        'gatewayOrderId': 'gwo_missing',
        'gatewayPaymentId': 'pay_unk',
        'amountMinor': 1900,
        'currency': 'INR',
      });
      expect(status, 409);
      expect(json['error']['code'], 'unknown_gateway_order');
    });
  });

  group('client-side verification', () {
    test(
      'verify records the payment as PENDING, then the webhook reaches VERIFIED',
      () async {
        final res = await _createOrder(ctx, idem: 'verify-r');
        final ref = (res['json'] as Map)['publicReference'] as String;
        final gwo =
            (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
        const gwp = 'pay_client';
        final sig = Hmac(
          sha256,
          utf8.encode(_secret),
        ).convert(utf8.encode('$gwo|$gwp')).toString();
        final (status, json) = await _post(
          '${ctx.baseUrl}/api/v1/funding/$ref/verify',
          {'orderId': gwo, 'paymentId': gwp, 'signature': sig},
        );
        expect(status, 200);
        expect(json['status'], 'PAYMENT_PENDING');
        expect(json['orderId'], gwo);
        final (_, st) = await _status(ctx, ref);
        expect(st['status'], 'PAYMENT_PENDING');
        expect(
          ctx.store.listPaymentsForOrder(ref).single.status.name,
          'pending',
        );

        // The gateway webhook then confirms the money without crashing on the
        // payment row already recorded under the gateway order.
        final (cs, cj) = await _complete(ctx, ref, 'success');
        expect(cs, 200);
        expect(cj['status'], 'VERIFIED');
        final payments = ctx.store.listPaymentsForOrder(ref);
        expect(payments.length, 1);
        expect(payments.single.status.name, 'verified');
      },
    );

    test('verify is idempotent for an already-paid order', () async {
      final res = await _createOrder(ctx, idem: 'verify-paid');
      final ref = (res['json'] as Map)['publicReference'] as String;
      final gwo = (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
      await _complete(ctx, ref, 'success');
      final sig = Hmac(
        sha256,
        utf8.encode(_secret),
      ).convert(utf8.encode('$gwo|pay_z')).toString();
      final (status, json) = await _post(
        '${ctx.baseUrl}/api/v1/funding/$ref/verify',
        {'orderId': gwo, 'paymentId': 'pay_z', 'signature': sig},
      );
      expect(status, 200);
      expect(json['status'], 'VERIFIED');
    });

    test('verify with a bad signature is 401', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final gwo = (res['json'] as Map)['checkout']['gatewayOrderId'] as String;
      final (status, json) = await _post(
        '${ctx.baseUrl}/api/v1/funding/$ref/verify',
        {'orderId': gwo, 'paymentId': 'pay_x', 'signature': 'deadbeef'},
      );
      expect(status, 401);
      expect(json['error']['code'], 'unauthorized');
      final (_, st) = await _status(ctx, ref);
      expect(st['status'], 'CREATED');
    });

    test('verify refuses a mismatched gateway order', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/$ref/verify',
        {'orderId': 'gwo_wrong', 'paymentId': 'pay_x', 'signature': 'x' * 64},
      );
      expect(status, 400);
    });

    test('verify of an unknown order is 404', () async {
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/TSPF_missing/verify',
        {'orderId': 'gwo_x', 'paymentId': 'pay_x', 'signature': 'x' * 64},
      );
      expect(status, 404);
    });

    test('verify requires orderId, paymentId and signature', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/$ref/verify',
        {'paymentId': 'pay_x'},
      );
      expect(status, 400);
    });
  });

  group('terms delivery', () {
    test('serves current terms bundle', () async {
      final (status, json) = await _get('${ctx.baseUrl}/api/v1/funding/terms');
      expect(status, 200);
      expect(json['version'], _terms);
      final docs = json['documents'] as List;
      final names = docs.map((d) => (d as Map)['name']).toSet();
      expect(
        names,
        containsAll(['overview', 'terms', 'privacy', 'refund', 'payment']),
      );
    });

    test('stale requested version flagged', () async {
      final (status, _) = await _get(
        '${ctx.baseUrl}/api/v1/funding/terms?version=2000-01-01',
      );
      expect(status, 422);
    });
  });

  group('history', () {
    test('admin key required', () async {
      final (status, _) = await _get('${ctx.baseUrl}/api/v1/funding/history');
      expect(status, 403);
    });

    test('returns sanitized orders without any gateway secrets', () async {
      await _createOrder(ctx, idem: 'h1');
      final (status, json) = await _get(
        '${ctx.baseUrl}/api/v1/funding/history',
        headers: {'X-Admin-Key': 'admin-key'},
      );
      expect(status, 200);
      final orders = json['orders'] as List;
      expect(orders, isNotEmpty);
      final entry = orders.last as Map;
      expect(entry.containsKey('publicReference'), isTrue);
      expect(entry.containsKey('amountMinor'), isTrue);
      expect(entry.containsKey('status'), isTrue);
      expect(entry.containsKey('gatewayOrderId'), isFalse);
      expect(entry.containsKey('checkout'), isFalse);
      expect(entry.containsKey('signature'), isFalse);
    });
  });

  group('reconciliation', () {
    test('clean ledger reports zero mismatches', () async {
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      await _complete(ctx, ref, 'success');
      final (status, json) = await _get(
        '${ctx.baseUrl}/api/v1/funding/reconciliation',
        headers: {'X-Admin-Key': 'admin-key'},
      );
      expect(status, 200);
      expect(json['mismatchCount'], 0);
      expect(json['mismatches'], isEmpty);
    });

    test('admin key required', () async {
      final (status, _) = await _get(
        '${ctx.baseUrl}/api/v1/funding/reconciliation',
      );
      expect(status, 403);
    });

    test('detects gateway/local drift', () async {
      await ctx.stop();
      ctx = TestContext();
      await ctx.start(failReconciliationProbe: true);
      await _createOrder(ctx);
      final (status, json) = await _get(
        '${ctx.baseUrl}/api/v1/funding/reconciliation',
        headers: {'X-Admin-Key': 'admin-key'},
      );
      expect(status, 200);
      expect(json['mismatchCount'], greaterThan(0));
    });
  });

  group('abuse protection', () {
    test('oversized request body rejected', () async {
      final big = {'fundingType': 'SUPPORT_49', 'pad': 'x' * (2 << 20)};
      final (status, _) = await _post(
        '${ctx.baseUrl}/api/v1/funding/orders',
        big,
      );
      expect(status, 413);
    });

    test('malformed JSON body is rejected as bad request', () async {
      final request =
          http.Request(
              'POST',
              Uri.parse('${ctx.baseUrl}/api/v1/funding/orders'),
            )
            ..headers['content-type'] = 'application/json'
            ..bodyBytes = utf8.encode('{not valid json');
      final response = await http.Response.fromStream(await request.send());
      expect(response.statusCode, 400);
    });

    test('excessive order volume is rate limited', () async {
      var got429 = false;
      for (var i = 0; i < 12; i++) {
        final (status, _) = await _post(
          '${ctx.baseUrl}/api/v1/funding/orders',
          {
            'fundingType': 'SUPPORT_49',
            'termsVersion': _terms,
            'accepted': true,
          },
        );
        if (status == 429) {
          got429 = true;
          break;
        }
      }
      expect(got429, isTrue);
    });
  });

  group('non-simulated mode', () {
    test('checkout simulator route is disabled', () async {
      await ctx.stop();
      ctx = TestContext();
      await ctx.start(gatewayMode: 'hosted');
      final res = await _createOrder(ctx);
      final ref = (res['json'] as Map)['publicReference'] as String;
      final (status, _) = await _complete(ctx, ref, 'success');
      expect(status, 403);
    });
  });

  test('unpaid orders do not drift to verified', () async {
    final res = await _createOrder(ctx);
    final ref = (res['json'] as Map)['publicReference'] as String;
    final (s, st) = await _status(ctx, ref);
    expect(s, 200);
    expect(
      FundingStatus.fromWire(st['status'] as String),
      FundingStatus.created,
    );
  });
}
