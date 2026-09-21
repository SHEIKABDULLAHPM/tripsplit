import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tripsplit_funding_server/domain/funding_status.dart';
import 'package:tripsplit_funding_server/domain/funding_type.dart';
import 'package:tripsplit_funding_server/domain/models.dart';
import 'package:tripsplit_funding_server/gw/payment_gateway.dart';
import 'package:tripsplit_funding_server/gw/razorpay_gateway.dart';

const _keyId = 'rzp_test_key';
const _keySecret = 'secret-key';
const _webhookSecret = 'webhook-secret';

FundingOrder _order() => FundingOrder(
  publicReference: 'TSPF_test',
  fundingType: FundingType.fromWire('SUPPORT_49')!,
  amountMinor: 4900,
  currency: 'INR',
  status: FundingStatus.created,
  termsVersion: '2026-09-21',
  createdAt: '2026-09-01T00:00:00Z',
  idempotencyKey: null,
);

RazorpayGateway _gateway(http.Client client) => RazorpayGateway(
  keyId: _keyId,
  keySecret: _keySecret,
  webhookSecret: _webhookSecret,
  client: client,
);

String _sign(List<int> body, String secret) =>
    Hmac(sha256, utf8.encode(secret)).convert(body).toString();

Map<String, dynamic> _event({
  required String name,
  String paymentId = 'pay_1',
  String orderId = 'order_X',
  int amount = 4900,
  String currency = 'INR',
}) => {
  'entity': 'event',
  'event': name,
  'account_id': 'acc_123',
  'payload': {
    'payment': {
      'entity': {
        'id': paymentId,
        'order_id': orderId,
        'amount': amount,
        'currency': currency,
        'status': 'captured',
      },
    },
    'order': {
      'entity': {
        'id': orderId,
        'amount': amount,
        'currency': currency,
        'status': 'paid',
      },
    },
  },
};

void main() {
  group('adapter identity', () {
    test('exposes the razorpay transport and public key id', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(gateway.transportName, 'razorpay');
      expect(gateway.signatureHeaderName, 'X-Razorpay-Signature');
      expect(gateway.publicKeyId, _keyId);
    });
  });

  group('createOrder', () {
    test('posts server-authoritative amount under basic auth', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'id': 'order_X', 'amount': 4900, 'currency': 'INR'}),
          200,
        );
      });
      final result = await _gateway(client).createOrder(_order());
      expect(result.gatewayOrderId, 'order_X');
      expect(result.checkoutInfo['mode'], 'hosted');
      expect(result.checkoutInfo['keyId'], _keyId);

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/orders');
      expect(
        captured.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('$_keyId:$_keySecret'))}',
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['amount'], 4900);
      expect(body['currency'], 'INR');
      expect(body['receipt'], 'TSPF_test');
      expect(body['payment_capture'], 1);
      expect((body['notes'] as Map)['publicReference'], 'TSPF_test');
    });

    test('non-2xx response becomes a gateway operation exception', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'description': 'Invalid amount'},
          }),
          400,
        ),
      );
      await expectLater(
        _gateway(client).createOrder(_order()),
        throwsA(
          isA<GatewayOperationException>().having(
            (e) => e.code,
            'code',
            'razorpay_order_failed',
          ),
        ),
      );
    });

    test(
      'unreachable transport becomes a gateway operation exception',
      () async {
        final client = MockClient((_) async => throw Exception('boom'));
        await expectLater(
          _gateway(client).createOrder(_order()),
          throwsA(
            isA<GatewayOperationException>().having(
              (e) => e.code,
              'code',
              'razorpay_unreachable',
            ),
          ),
        );
      },
    );
  });

  group('fetchPayment', () {
    test('no payments reports state none', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/orders/order_X/payments');
        return http.Response(jsonEncode({'items': []}), 200);
      });
      final entry = await _gateway(client).fetchPayment('order_X');
      expect(entry.hasPayment, isFalse);
      expect(entry.state, 'none');
      expect(entry.gatewayPaymentId, isNull);
    });

    test('maps a captured payment', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pay_1',
                'amount': 4900,
                'currency': 'INR',
                'status': 'captured',
              },
            ],
          }),
          200,
        ),
      );
      final entry = await _gateway(client).fetchPayment('order_X');
      expect(entry.hasPayment, isTrue);
      expect(entry.state, 'captured');
      expect(entry.gatewayPaymentId, 'pay_1');
      expect(entry.amountMinor, 4900);
      expect(entry.currency, 'INR');
    });

    test('normalizes razorpay payment statuses', () async {
      const statuses = {
        'authorized': 'authorized',
        'captured': 'captured',
        'failed': 'failed',
        'refunded': 'refunded',
        'processing': 'pending',
      };
      for (final entry in statuses.entries) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'pay_1',
                  'amount': 4900,
                  'currency': 'INR',
                  'status': entry.key,
                },
              ],
            }),
            200,
          ),
        );
        final fetched = await _gateway(client).fetchPayment('order_X');
        expect(fetched.state, entry.value);
      }
    });
  });

  group('verifyClientSignature', () {
    test('accepts the correct HMAC over order id and payment id', () {
      final signature = _sign(utf8.encode('order_X|pay_1'), _keySecret);
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => gateway.verifyClientSignature(
          order: _order(),
          gatewayOrderId: 'order_X',
          gatewayPaymentId: 'pay_1',
          signature: signature,
        ),
        returnsNormally,
      );
    });

    test('rejects a tampered signature', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => gateway.verifyClientSignature(
          order: _order(),
          gatewayOrderId: 'order_X',
          gatewayPaymentId: 'pay_1',
          signature: '0' * 64,
        ),
        throwsA(isA<GatewaySignatureException>()),
      );
    });
  });

  group('webhooks', () {
    test(
      'verifyAndExtractPayload accepts a body signed with the webhook secret',
      () {
        const payload = '{"event":"payment.captured"}';
        final body = Uint8List.fromList(utf8.encode(payload));
        final gateway = _gateway(
          MockClient((_) async => http.Response('{}', 200)),
        );
        final extracted = gateway.verifyAndExtractPayload(body, {
          razorpayWebhookSignatureHeader: _sign(body, _webhookSecret),
        });
        expect(jsonDecode(extracted)['event'], 'payment.captured');
      },
    );

    test('missing signature header is rejected', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => gateway.verifyAndExtractPayload(Uint8List(0), const {}),
        throwsA(isA<GatewaySignatureException>()),
      );
    });

    test('body signed with the wrong secret is rejected', () {
      final body = Uint8List.fromList(
        utf8.encode('{"event":"payment.captured"}'),
      );
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => gateway.verifyAndExtractPayload(body, {
          razorpayWebhookSignatureHeader: _sign(body, 'attacker'),
        }),
        throwsA(isA<GatewaySignatureException>()),
      );
    });
  });

  group('parseEvent', () {
    test('payment.captured maps to order.captured with a stable event id', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      final event = gateway.parseEvent(
        jsonEncode(_event(name: 'payment.captured')),
      );
      expect(event.eventType, 'order.captured');
      expect(event.gatewayOrderId, 'order_X');
      expect(event.gatewayPaymentId, 'pay_1');
      expect(event.amountMinor, 4900);
      expect(event.currency, 'INR');
      expect(event.gatewayEventId, 'pay_1:payment.captured');
      expect(event.isSuccess, isTrue);
    });

    test('maps order.paid, payment.failed and order.cancelled', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        gateway.parseEvent(jsonEncode(_event(name: 'order.paid'))).eventType,
        'order.captured',
      );
      expect(
        gateway
            .parseEvent(jsonEncode(_event(name: 'payment.failed')))
            .eventType,
        'order.failed',
      );
      expect(
        gateway
            .parseEvent(jsonEncode(_event(name: 'order.cancelled')))
            .eventType,
        'order.cancelled',
      );
    });

    test(
      'falls back to the order entity id when only the order is present',
      () {
        final gateway = _gateway(
          MockClient((_) async => http.Response('{}', 200)),
        );
        final event = gateway.parseEvent(
          jsonEncode({
            'entity': 'event',
            'event': 'order.cancelled',
            'payload': {
              'order': {
                'entity': {'id': 'order_X'},
              },
            },
          }),
        );
        expect(event.gatewayOrderId, 'order_X');
        expect(event.gatewayPaymentId, 'order_X_order.cancelled');
      },
    );

    test('rejects unsupported and malformed payloads', () {
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => gateway.parseEvent(jsonEncode(_event(name: 'payment.foo'))),
        throwsFormatException,
      );
      expect(() => gateway.parseEvent('not json'), throwsFormatException);
      expect(
        () => gateway.parseEvent(jsonEncode({'event': 'payment.captured'})),
        throwsFormatException,
      );
    });

    test('signed webhook round-trips through verification and parsing', () {
      final body = Uint8List.fromList(
        utf8.encode(jsonEncode(_event(name: 'payment.captured'))),
      );
      final gateway = _gateway(
        MockClient((_) async => http.Response('{}', 200)),
      );
      final raw = gateway.verifyAndExtractPayload(body, {
        razorpayWebhookSignatureHeader: _sign(body, _webhookSecret),
      });
      final event = gateway.parseEvent(raw);
      expect(event.eventType, 'order.captured');
      expect(event.gatewayPaymentId, 'pay_1');
    });
  });
}
