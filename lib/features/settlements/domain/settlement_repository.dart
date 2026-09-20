import 'settlement.dart';

/// Abstract contract for persisting [Settlement] entities.
///
/// Implementations live in the data layer; the domain and presentation layers
/// depend only on this interface. Settlements record transfers between members
/// and are never derived from other tables.
abstract interface class SettlementRepository {
  Stream<List<Settlement>> watchByTrip(int tripId);
  Future<List<Settlement>> getByTrip(int tripId);

  /// Records a settlement payment from [fromMemberId] to [toMemberId].
  ///
  /// [amountMinor] is the obligation being recorded and [paidMinor] the cash
  /// transferred in this step. The payment cannot exceed the outstanding debt
  /// still owed between the pair. When the obligation's remaining debt is
  /// zero, a [ValidationException] is thrown.
  Future<void> recordPayment({
    required int tripId,
    required int fromMemberId,
    required int toMemberId,
    required int amountMinor,
    required int paidMinor,
    String? note,
  });

  /// Replaces the paid amount of the settlement identified by [settlementId].
  ///
  /// [paidMinor] must be between 0 and the settlement's obligation. Setting it
  /// to 0 marks the settlement unpaid; setting it to the full obligation marks
  /// it paid. The `paidAt` timestamp is updated/cleared accordingly.
  Future<void> setPaidAmount({
    required int settlementId,
    required int paidMinor,
  });

  Future<void> deleteById(int id);
}
