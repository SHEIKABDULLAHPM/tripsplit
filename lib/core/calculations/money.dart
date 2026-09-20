import '../errors/app_exception.dart';

/// Pure-Dart money utilities operating on integer minor units.
///
/// Every monetary value in TripSplit is stored as an integer in the smallest
/// unit of the trip currency (paise for INR). Floating-point money never
/// exists in the domain.
abstract final class MoneyCalculator {
  MoneyCalculator._();

  static const String _currencySymbol = '₹';

  /// Parses a human-entered amount such as `"365.40"`, `"1,650"` or
  /// `"₹ 125.5"` into integer minor units (e.g. `36540`).
  ///
  /// The input may contain currency symbols, thousands separators and
  /// whitespace; anything that is not a digit or a decimal point is ignored.
  ///
  /// Throws a [ValidationException] when [input] is empty, malformed, has a
  /// leading minus sign, or has more than two decimal places. Money amounts
  /// in TripSplit are never negative, so negative inputs are rejected rather
  /// than silently converted.
  static int parseToMinor(String input, {String label = 'Amount'}) {
    final trimmed = input.trim();
    if (trimmed.contains('-')) {
      throw ValidationException('$label cannot be negative.');
    }
    final cleaned = trimmed.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) {
      throw ValidationException('$label is required.');
    }

    final parts = cleaned.split('.');
    if (parts.length > 2) {
      throw ValidationException('$label is invalid.');
    }
    if (parts.length == 2 && parts[1].length > 2) {
      throw ValidationException('$label has too many decimal places.');
    }

    final rupees = int.tryParse(parts[0]);
    if (rupees == null) {
      throw ValidationException('$label is invalid.');
    }

    final paise = parts.length == 2 && parts[1].isNotEmpty
        ? _padPaise(parts[1])
        : 0;

    return rupees * 100 + paise;
  }

  /// Like [parseToMinor] but returns `null` instead of throwing for invalid
  /// input (e.g. for live form previews).
  static int? parseToMinorOrNull(String input, {String label = 'Amount'}) {
    try {
      return parseToMinor(input, label: label);
    } on AppException {
      return null;
    }
  }

  /// Formats [minor] as a human-readable Indian number, e.g. `₹1,650.00`.
  ///
  /// Negative amounts render as `-₹198.80`.
  static String format(int minor) => _format(minor, withSymbol: true);

  /// Like [format] but without the currency symbol, e.g. `1,650.00`.
  static String formatNoSymbol(int minor) => _format(minor, withSymbol: false);

  static String _format(int minor, {required bool withSymbol}) {
    final sign = minor < 0 ? '-' : '';
    final magnitude = minor.abs();
    final rupees = magnitude ~/ 100;
    final paise = magnitude % 100;
    final symbol = withSymbol ? _currencySymbol : '';
    return '$sign$symbol${_groupIndian(rupees)}'
        '.${paise.toString().padLeft(2, '0')}';
  }

  static int _padPaise(String value) => int.parse(value.padRight(2, '0'));

  /// Groups digits using Indian numbering: a rightmost group of three, then
  /// groups of two working right-to-left (so the leftmost group is one or two
  /// digits). For example `1234567` renders as `12,34,567`.
  static String _groupIndian(int value) {
    final digits = value.toString();
    if (digits.length <= 3) {
      return digits;
    }

    final lastThree = digits.substring(digits.length - 3);
    final prefix = digits.substring(0, digits.length - 3);

    final groups = <String>[];
    var rest = prefix;
    while (rest.length > 2) {
      groups.add(rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      groups.add(rest);
    }

    return '${groups.reversed.join(',')},$lastThree';
  }
}
