import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/features/funding/data/funding_api_client.dart';
import 'package:tripsplit/features/funding/data/funding_repository.dart';
import 'package:tripsplit/features/funding/domain/funding_exception.dart';
import 'package:tripsplit/features/funding/domain/funding_info.dart';

/// Captures requests instead of hitting the network.
class _RecordingClient extends FundingApiClient {
  _RecordingClient() : super(baseUrl: 'http://funding-test.invalid');

  final List<(String, Map<String, Object?>)> posts = [];
  final List<String> gets = [];

  Map<String, dynamic> Function(String path, Map<String, Object?> body)?
  _postResponder;
  Map<String, dynamic> Function(String path)? _getResponder;

  void respondToPost(
    Map<String, dynamic> Function(String path, Map<String, Object?> body)
    responder,
  ) {
    _postResponder = responder;
  }

  void respondToGet(Map<String, dynamic> Function(String path) responder) {
    _getResponder = responder;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    posts.add((path, Map.unmodifiable(body)));
    final responder = _postResponder;
    if (responder == null) {
      throw StateError('No post responder registered for $path');
    }
    return responder(path, body);
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    gets.add(path);
    final responder = _getResponder;
    if (responder == null) {
      throw StateError('No get responder registered for $path');
    }
    return responder(path);
  }
}

Map<String, dynamic> _orderJson({
  required String mode,
  Object? amountMinor = 4900,
  String status = 'CREATED',
}) => {
  'publicReference': 'TS_1010',
  'fundingType': 'SUPPORT_49',
  'amountMinor': amountMinor,
  'currency': 'INR',
  'status': status,
  'termsVersion': '2026-09-01',
  'checkout': {'mode': mode},
};

void main() {
  late _RecordingClient client;
  late FundingRepository repo;

  setUp(() {
    client = _RecordingClient();
    repo = FundingRepository(client);
  });

  group('FundingRepository', () {
    test('createOrder posts the exact payload the server expects', () async {
      client.respondToPost((_, _) => _orderJson(mode: 'simulated'));

      final order = await repo.createOrder(
        FundingType.support49,
        idempotencyKey: 'flutter_idem',
      );

      expect(order.amountMinor, 4900);
      expect(order.status, FundingStatus.created);
      final (path, body) = client.posts.single;
      expect(path, '/api/v1/funding/orders');
      expect(body['fundingType'], 'SUPPORT_49');
      expect(body['termsVersion'], '2026-09-01');
      expect(body['accepted'], true);
      expect(body['idempotencyKey'], 'flutter_idem');
    });

    test('createOrder sends the requested terms version', () async {
      client.respondToPost((_, _) => _orderJson(mode: 'hosted'));

      await repo.createOrder(
        FundingType.future199,
        idempotencyKey: 'key',
        termsVersion: '2025-01-01',
      );

      expect(client.posts.single.$2['termsVersion'], '2025-01-01');
    });

    test('verifyPayment posts the checkout signature to the server', () async {
      client.respondToPost(
        (_, _) => _orderJson(mode: 'hosted', status: 'PAYMENT_PENDING'),
      );

      final order = await repo.verifyPayment(
        publicReference: 'TS_1010',
        orderId: 'order_X',
        paymentId: 'pay_1',
        signature: '0123abcd',
      );

      expect(order.status, FundingStatus.paymentPending);
      final (path, body) = client.posts.single;
      expect(path, '/api/v1/funding/TS_1010/verify');
      expect(body['orderId'], 'order_X');
      expect(body['paymentId'], 'pay_1');
      expect(body['signature'], '0123abcd');
    });

    test('fetchHistory skips malformed entries', () async {
      client.respondToGet(
        (path) => {
          'orders': [_orderJson(mode: 'hosted'), 'garbage'],
        },
      );

      final orders = await repo.fetchHistory();

      expect(client.gets, ['/api/v1/funding/history']);
      expect(orders, hasLength(1));
      expect(orders.single.publicReference, 'TS_1010');
    });

    test('mapOrder wraps a structurally invalid payload', () {
      expect(
        () => mapOrder({'amountMinor': 'not-an-int'}),
        throwsA(
          isA<FundingException>().having(
            (e) => e.kind,
            'kind',
            FundingFailureKind.malformedResponse,
          ),
        ),
      );
    });
  });
}
