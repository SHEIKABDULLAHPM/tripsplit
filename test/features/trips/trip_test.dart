import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/features/trips/domain/trip.dart';

void main() {
  // DateTime's constructor is not `const`, so test fixtures use `final`.
  final now = DateTime(2026, 9, 12);

  final trip = Trip(
    id: 1,
    name: 'Summer in Rome',
    currencyCode: 'INR',
    createdAt: now,
    updatedAt: now,
  );

  group('Trip', () {
    test('supports value equality', () {
      final same = Trip(
        id: 1,
        name: 'Summer in Rome',
        currencyCode: 'INR',
        createdAt: now,
        updatedAt: now,
      );
      expect(trip, same);
      expect(trip.hashCode, same.hashCode);
    });

    test('supports copyWith', () {
      final renamed = trip.copyWith(name: 'Autumn in Florence');
      expect(renamed.name, 'Autumn in Florence');
      expect(renamed.id, trip.id);
    });

    test('defaults currency to USD', () {
      final minimal = Trip(
        id: 2,
        name: 'Minimal',
        createdAt: now,
        updatedAt: now,
      );
      expect(minimal.currencyCode, 'INR');
    });

    test('round-trips through JSON', () {
      final json = trip.toJson();
      final restored = Trip.fromJson(json);
      expect(restored, trip);
    });
  });
}
