import 'member.dart';

/// Abstract contract for persisting [Member] entities.
///
/// Implementations live in the data layer; the domain and presentation layers
/// depend only on this interface.
abstract interface class MemberRepository {
  Stream<List<Member>> watchByTrip(int tripId);
  Future<List<Member>> getByTrip(int tripId);
  Future<Member?> findById(int id);

  /// Inserts a new member or updates an existing one (id > 0).
  ///
  /// Returns the persisted member (with its assigned id).
  Future<Member> save(Member member);
  Future<void> deleteById(int id);
}
