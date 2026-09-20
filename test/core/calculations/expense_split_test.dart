import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';

void main() {
  const splitter = EqualExpenseSplitter();

  group('EqualExpenseSplitter', () {
    test('splits evenly when the total divides exactly', () {
      final shares = splitter.split(totalMinor: 12000, memberIds: [1, 2, 3]);
      expect(shares.map((s) => (s.memberId, s.amountMinor)), [
        (1, 4000),
        (2, 4000),
        (3, 4000),
      ]);
    });

    test('uses largest-remainder rounding for a non-divisible total', () {
      final shares = splitter.split(totalMinor: 10000, memberIds: [1, 2, 3]);
      expect(shares.map((s) => (s.memberId, s.amountMinor)), [
        (1, 3334),
        (2, 3333),
        (3, 3333),
      ]);
    });

    test('always sums shares exactly back to the total', () {
      for (final total in [1, 7, 10000, 10001, 73360]) {
        for (final count in [1, 2, 3, 4, 5]) {
          final memberIds = [for (var i = 0; i < count; i++) i + 1];
          final sum = splitter
              .split(totalMinor: total, memberIds: memberIds)
              .fold<int>(0, (s, share) => s + share.amountMinor);
          expect(sum, total, reason: 'total=$total count=$count');
        }
      }
    });

    test('is deterministic on every call', () {
      final first = splitter.split(totalMinor: 73360, memberIds: [1, 2, 3]);
      final second = splitter.split(totalMinor: 73360, memberIds: [1, 2, 3]);
      expect(first.map((s) => s.amountMinor), second.map((s) => s.amountMinor));
    });

    test('handles a single participant', () {
      final shares = splitter.split(totalMinor: 500, memberIds: [9]);
      expect(shares, hasLength(1));
      expect(shares.single.memberId, 9);
      expect(shares.single.amountMinor, 500);
    });

    test('exact rounding examples from specification', () {
      // ₹10.00 / 3
      final r10 = splitter.split(totalMinor: 1000, memberIds: [1, 2, 3]);
      expect(r10.map((s) => s.amountMinor), [334, 333, 333]);
      expect(r10.fold<int>(0, (s, share) => s + share.amountMinor), 1000);

      // ₹1.00 / 3
      final r1 = splitter.split(totalMinor: 100, memberIds: [1, 2, 3]);
      expect(r1.map((s) => s.amountMinor), [34, 33, 33]);
      expect(r1.fold<int>(0, (s, share) => s + share.amountMinor), 100);

      // ₹0.01 / 3
      final r01 = splitter.split(totalMinor: 1, memberIds: [1, 2, 3]);
      expect(r01.map((s) => s.amountMinor), [1, 0, 0]);
      expect(r01.fold<int>(0, (s, share) => s + share.amountMinor), 1);

      // ₹100.01 / 3
      final r10001 = splitter.split(totalMinor: 10001, memberIds: [1, 2, 3]);
      expect(r10001.map((s) => s.amountMinor), [3334, 3334, 3333]);
      expect(r10001.fold<int>(0, (s, share) => s + share.amountMinor), 10001);

      // ₹999.99 / 7
      final r99999 = splitter.split(
        totalMinor: 99999,
        memberIds: [1, 2, 3, 4, 5, 6, 7],
      );
      expect(r99999.map((s) => s.amountMinor), [
        14286,
        14286,
        14286,
        14286,
        14285,
        14285,
        14285,
      ]);
      expect(r99999.fold<int>(0, (s, share) => s + share.amountMinor), 99999);

      // ₹1,000.00 / 6
      final r1000 = splitter.split(
        totalMinor: 100000,
        memberIds: [1, 2, 3, 4, 5, 6],
      );
      expect(r1000.map((s) => s.amountMinor), [
        16667,
        16667,
        16667,
        16667,
        16666,
        16666,
      ]);
      expect(r1000.fold<int>(0, (s, share) => s + share.amountMinor), 100000);
    });

    test('rejects an empty participant list and negative totals', () {
      expect(
        () => splitter.split(totalMinor: 100, memberIds: []),
        throwsArgumentError,
      );
      expect(
        () => splitter.split(totalMinor: -1, memberIds: [1]),
        throwsArgumentError,
      );
    });
  });
}
