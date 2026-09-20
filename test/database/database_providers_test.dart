import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/injection/database_providers.dart';

void main() {
  group('database providers', () {
    test('provide a singleton database instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(appDatabaseProvider);
      final second = container.read(appDatabaseProvider);

      expect(identical(first, second), isTrue);
    });

    test('derive DAOs from the database provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(tripDaoProvider),
        same(container.read(appDatabaseProvider).tripDao),
      );
      expect(
        container.read(memberDaoProvider),
        same(container.read(appDatabaseProvider).memberDao),
      );
      expect(
        container.read(contributionDaoProvider),
        same(container.read(appDatabaseProvider).contributionDao),
      );
      expect(
        container.read(expenseDaoProvider),
        same(container.read(appDatabaseProvider).expenseDao),
      );
      expect(
        container.read(settlementDaoProvider),
        same(container.read(appDatabaseProvider).settlementDao),
      );
    });

    test('allows overriding the database (test seams)', () {
      final original = ProviderContainer();
      addTearDown(original.dispose);

      final db = original.read(appDatabaseProvider);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(container.read(appDatabaseProvider), same(db));
    });
  });
}
