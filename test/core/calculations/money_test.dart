import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/money.dart';
import 'package:tripsplit/core/errors/app_exception.dart';

void main() {
  group('MoneyCalculator.parseToMinor', () {
    test('parses whole rupees', () {
      expect(MoneyCalculator.parseToMinor('100'), 10000);
      expect(MoneyCalculator.parseToMinor('0'), 0);
    });

    test('parses decimal amounts', () {
      expect(MoneyCalculator.parseToMinor('365.40'), 36540);
      expect(MoneyCalculator.parseToMinor('365.4'), 36540);
      expect(MoneyCalculator.parseToMinor('365.04'), 36504);
      expect(MoneyCalculator.parseToMinor('0.01'), 1);
    });

    test('ignores currency, thousands separators and whitespace', () {
      expect(MoneyCalculator.parseToMinor('₹ 1,650.00'), 165000);
      expect(MoneyCalculator.parseToMinor('1,650'), 165000);
      expect(MoneyCalculator.parseToMinor(' 125.5 '), 12550);
    });

    test('rejects empty, malformed and over-precise input', () {
      expect(
        () => MoneyCalculator.parseToMinor(''),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => MoneyCalculator.parseToMinor('abc'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => MoneyCalculator.parseToMinor('12.345'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects negative amounts', () {
      expect(
        () => MoneyCalculator.parseToMinor('-100'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => MoneyCalculator.parseToMinor('-1'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => MoneyCalculator.parseToMinor('₹-50.5'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('trailing dot is valid even without paise', () {
      expect(MoneyCalculator.parseToMinor('100.'), 10000);
    });

    test('leading decimal point with no rupees digit is rejected', () {
      expect(
        () => MoneyCalculator.parseToMinor('.50'),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('MoneyCalculator.format', () {
    test('formats whole rupees with paise', () {
      expect(MoneyCalculator.format(165000), '₹1,650.00');
      expect(MoneyCalculator.format(36540), '₹365.40');
      expect(MoneyCalculator.format(500), '₹5.00');
      expect(MoneyCalculator.format(1), '₹0.01');
      expect(MoneyCalculator.format(0), '₹0.00');
    });

    test('uses Indian digit grouping', () {
      expect(MoneyCalculator.format(123456789), '₹12,34,567.89');
      expect(MoneyCalculator.format(100000), '₹1,000.00');
    });

    test('renders negatives with a leading minus', () {
      expect(MoneyCalculator.format(-19880), '-₹198.80');
    });
  });
}
