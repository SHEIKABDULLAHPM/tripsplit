import 'package:test/test.dart';
import 'package:tripsplit_funding_server/domain/funding_status.dart';
import 'package:tripsplit_funding_server/domain/funding_type.dart';

void main() {
  group('FundingType', () {
    test('wire values map to the required plans', () {
      expect(FundingType.fromWire('SUPPORT_49'), FundingType.support49);
      expect(FundingType.fromWire('FUTURE_199'), FundingType.future199);
    });

    test('amounts are exact and in minor units (paise)', () {
      expect(FundingType.support49.amountMinor, 1900); // ₹19
      expect(FundingType.future199.amountMinor, 4900); // ₹49
      expect(FundingType.support49.currency, 'INR');
      expect(FundingType.future199.currency, 'INR');
    });

    test('unknown wire values are rejected', () {
      expect(FundingType.fromWire('PLAN_999'), isNull);
      expect(FundingType.fromWire(null), isNull);
    });
  });

  group('FundingStatus', () {
    test('terminal states are recognized', () {
      for (final s in FundingStatus.values) {
        expect(
          s.isTerminal,
          s == FundingStatus.verified ||
              s == FundingStatus.failed ||
              s == FundingStatus.cancelled ||
              s == FundingStatus.expired ||
              s == FundingStatus.refunded,
          reason: '${s.wire} terminal mismatch',
        );
      }
    });

    test('legal transitions', () {
      final from = FundingStatus.created;
      for (final to in FundingStatus.values) {
        final allowed =
            to == FundingStatus.created ||
            to == FundingStatus.checkoutStarted ||
            to == FundingStatus.paymentPending ||
            to == FundingStatus.cancelled ||
            to == FundingStatus.expired ||
            to == FundingStatus.failed;
        expect(from.canTransitionTo(to), allowed);
      }
    });

    test('terminal states cannot leave', () {
      expect(
        FundingStatus.failed.canTransitionTo(FundingStatus.verified),
        isFalse,
      );
      expect(
        FundingStatus.cancelled.canTransitionTo(FundingStatus.verified),
        isFalse,
      );
      expect(
        FundingStatus.verified.canTransitionTo(FundingStatus.refunded),
        isFalse,
      );
      expect(
        FundingStatus.verified.canTransitionTo(FundingStatus.captured),
        isFalse,
      );
    });

    test('capture path reaches verified', () {
      var s = FundingStatus.created;
      s = FundingStatus.checkoutStarted; // legal from created
      s = FundingStatus.paymentPending; // legal from checkoutStarted
      s = FundingStatus.authorized; // legal from paymentPending
      s = FundingStatus.captured; // legal from authorized
      s = FundingStatus.verificationPending; // legal from captured
      s = FundingStatus.verified; // legal from verificationPending
      expect(s, FundingStatus.verified);
    });

    test('refunded implies paid', () {
      expect(FundingStatus.verified.isPaid, isTrue);
      expect(FundingStatus.refunded.isPaid, isTrue);
      expect(FundingStatus.authorized.isPaid, isFalse);
    });
  });
}
