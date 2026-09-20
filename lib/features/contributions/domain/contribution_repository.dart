import 'contribution.dart';

/// Abstract contract for persisting [Contribution] entities.
abstract interface class ContributionRepository {
  Stream<List<Contribution>> watchByTrip(int tripId);
  Future<List<Contribution>> getByTrip(int tripId);
  Future<void> save(Contribution contribution);
  Future<void> deleteById(int id);
}
