import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/features/funding/domain/funding_info.dart';

void main() {
  group('FundingType', () {
    test('wire values match the server contract', () {
      expect(FundingType.support49.wire, 'SUPPORT_49');
      expect(FundingType.future199.wire, 'FUTURE_199');
      expect(FundingType.fromWire('SUPPORT_49'), FundingType.support49);
      expect(FundingType.fromWire('FUTURE_199'), FundingType.future199);
    });

    test('unknown wire falls back but is never used for charging', () {
      expect(FundingType.fromWire('SOMETHING_ELSE'), FundingType.support49);
    });

    test('display price is UI-only and never the stored amount', () {
      expect(FundingType.support49.displayRupees, 19);
      expect(FundingType.future199.displayRupees, 49);
    });
  });

  group('FundingStatus', () {
    test('wire round-trips', () {
      expect(FundingStatus.fromWire('VERIFIED'), FundingStatus.verified);
      expect(FundingStatus.fromWire(null), FundingStatus.created);
    });

    test('isPending reflects an in-flight order only', () {
      expect(FundingStatus.created.isPending, isTrue);
      expect(FundingStatus.paymentPending.isPending, isTrue);
      expect(FundingStatus.verified.isPending, isFalse);
      expect(FundingStatus.refunded.isPending, isFalse);
      expect(FundingStatus.failed.isPending, isFalse);
      expect(FundingStatus.cancelled.isPending, isFalse);
      expect(FundingStatus.expired.isPending, isFalse);
    });
  });

  group('FundingOrder', () {
    Map<String, dynamic> orderJson({
      String mode = 'hosted',
      int amount = 4900,
      String status = 'CREATED',
      String? note,
    }) => {
      'publicReference': 'TS_9090',
      'fundingType': 'SUPPORT_49',
      'amountMinor': amount,
      'currency': 'INR',
      'status': status,
      'termsVersion': '2026-09-21',
      'checkout': {'mode': mode},
      'note': ?note,
    };

    test('hosted order carries no sandbox note and is not simulated', () {
      final order = FundingOrder.fromJson(orderJson());
      expect(order.checkoutMode, 'hosted');
      expect(order.needsSimulatedCheckout, isFalse);
      expect(order.note, isEmpty);
    });

    test('simulated order exposes the sandbox checkout flag and note', () {
      final order = FundingOrder.fromJson(
        orderJson(mode: 'simulated', note: 'sandbox'),
      );
      expect(order.checkoutMode, 'simulated');
      expect(order.needsSimulatedCheckout, isTrue);
      expect(order.note, 'sandbox');
    });

    test('parseOrderJson rejects a non-object payload', () {
      expect(
        () => parseOrderJson('[1,2,3]'),
        throwsA(isA<FundingFormatException>()),
      );
    });

    test('hosted order carries the gateway order id and public key id', () {
      final order = FundingOrder.fromJson({
        ...orderJson(),
        'orderId': 'order_X',
        'keyId': 'rzp_test_key',
        'checkout': {
          'mode': 'hosted',
          'gatewayOrderId': 'order_X',
          'keyId': 'rzp_test_key',
        },
      });
      expect(order.orderId, 'order_X');
      expect(order.keyId, 'rzp_test_key');
      expect(order.canLaunchHostedCheckout, isTrue);
    });

    test('order id falls back to the checkout gatewayOrderId', () {
      final order = FundingOrder.fromJson({
        ...orderJson(),
        'checkout': {'mode': 'hosted', 'gatewayOrderId': 'order_Y'},
      });
      expect(order.orderId, 'order_Y');
      expect(order.keyId, isNull);
      expect(order.canLaunchHostedCheckout, isFalse);
    });

    test('simulated orders are never launchable as hosted', () {
      final order = FundingOrder.fromJson(
        orderJson(mode: 'simulated', note: 'sandbox'),
      );
      expect(order.canLaunchHostedCheckout, isFalse);
      expect(order.keyId, isNull);
      expect(order.orderId, isNull);
    });
  });

  group('FundingDocument', () {
    test('defaults draft and sections for partial payloads', () {
      final doc = FundingDocument.fromJson(const {'name': 'terms'});
      expect(doc.draft, isTrue);
      expect(doc.sections, isEmpty);
      expect(doc.title, isEmpty);
    });

    test('parses heading/body sections', () {
      final doc = FundingDocument.fromJson({
        'name': 'terms',
        'title': 'Funding Terms',
        'draft': true,
        'sections': [
          {'heading': 'A', 'body': 'One'},
          {'heading': 'B', 'body': 'Two'},
        ],
      });
      expect(doc.sections, hasLength(2));
      expect(doc.sections.first.heading, 'A');
      expect(doc.sections.last.body, 'Two');
    });
  });
}
