import 'trip.dart';

/// A member to be created together with a new trip.
class NewMemberDraft {
  const NewMemberDraft({required this.name, this.contributionMinor = 0});

  final String name;
  final int contributionMinor;
}

/// Abstract contract for persisting [Trip] entities.
///
/// Implementations live in the data layer; the domain and presentation layers
/// depend only on this interface.
abstract interface class TripRepository {
  Stream<List<Trip>> watchAll();
  Stream<Trip?> watchById(int id);
  Future<Trip?> findById(int id);

  /// Inserts a new trip or updates an existing one (id > 0).
  Future<void> save(Trip trip);
  Future<void> deleteById(int id);

  /// Creates a trip together with its initial members and their
  /// contributions inside a single transaction.
  ///
  /// [startLocation] seeds the journey's starting point (the app assumes the
  /// trip starts from somewhere such as the home city, e.g. Erode).
  Future<int> createWithSetup({
    required String name,
    required int budgetMinor,
    required List<NewMemberDraft> members,
    String? startLocation,
    DateTime? startDate,
    DateTime? endDate,
  });
}
