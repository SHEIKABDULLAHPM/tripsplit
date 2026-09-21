import 'package:drift/drift.dart';

import '../../../core/calculations/money.dart';
import '../../../core/calculations/settlements.dart';
import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/settlement.dart';
import '../domain/settlement_repository.dart';

/// Drift-backed [SettlementRepository].
class SettlementRepositoryImpl implements SettlementRepository {
  SettlementRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Settlement>> watchByTrip(int tripId) => _db.settlementDao
      .watchByTrip(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<Settlement>> getByTrip(int tripId) async =>
      (await _db.settlementDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<void> recordPayment({
    required int tripId,
    required int fromMemberId,
    required int toMemberId,
    required int amountMinor,
    required int paidMinor,
    String? note,
  }) async {
    if (fromMemberId == toMemberId) {
      throw const ValidationException(
        'A member cannot settle with themselves.',
      );
    }
    if (paidMinor <= 0) {
      throw const ValidationException(
        'Payment amount must be greater than zero.',
      );
    }

    final plan = await _currentSettlementPlan(tripId);
    final outstanding = SettlementCalculator.outstandingBetween(
      plan.suggestions,
      fromMemberId: fromMemberId,
      toMemberId: toMemberId,
    );

    if (paidMinor > outstanding) {
      throw ValidationException(
        'Payment of ${MoneyCalculator.format(paidMinor)} exceeds the '
        'outstanding amount of ${MoneyCalculator.format(outstanding)}.',
      );
    }

    final now = DateTime.now();
    final existing = await _db.settlementDao.getByTrip(tripId);
    SettlementRow? active;
    for (final row in existing) {
      if (row.fromMemberId == fromMemberId &&
          row.toMemberId == toMemberId &&
          row.amountPaidMinor < row.amountMinor) {
        active = row;
        break;
      }
    }

    if (active != null) {
      // The stored obligation may be stale: new expenses can grow the
      // outstanding amount for this pair after the row was created. Rebase
      // the row onto the fresh figure so amountPaidMinor never exceeds
      // amountMinor.
      final totalObligation = outstanding + active.amountPaidMinor;
      final newPaid = active.amountPaidMinor + paidMinor;
      final fullyPaid = newPaid >= totalObligation;
      await _db.settlementDao.updateById(
        active.id,
        SettlementsCompanion(
          amountMinor: Value(totalObligation),
          amountPaidMinor: Value(newPaid),
          paidAt: fullyPaid ? Value(now) : const Value.absent(),
          updatedAt: Value(now),
          note: Value(note ?? active.note),
        ),
      );
      return;
    }

    await _db.settlementDao.insert(
      SettlementsCompanion.insert(
        tripId: tripId,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
        amountMinor: Value(outstanding),
        amountPaidMinor: Value(paidMinor),
        note: Value(note),
        settledAt: Value(now),
        paidAt: Value(paidMinor >= outstanding ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> setPaidAmount({
    required int settlementId,
    required int paidMinor,
  }) async {
    if (paidMinor < 0) {
      throw const ValidationException('Paid amount cannot be negative.');
    }
    final row = await _db.settlementDao.getById(settlementId);
    if (row == null) return;

    final plan = await _currentSettlementPlan(row.tripId);
    final pairRows = (await _db.settlementDao.getByTrip(row.tripId))
        .where(
          (r) =>
              r.fromMemberId == row.fromMemberId &&
              r.toMemberId == row.toMemberId,
        )
        .toList();
    final alreadyPaid = pairRows.fold<int>(
      0,
      (sum, r) => sum + r.amountPaidMinor,
    );
    final remaining = SettlementCalculator.outstandingBetween(
      plan.suggestions,
      fromMemberId: row.fromMemberId,
      toMemberId: row.toMemberId,
    );
    // The live obligation reflects the current plan (which accounts for any
    // expenses added, edited or removed since the row was recorded), so the
    // edited value can never diverge from what is actually owed.
    final obligation = remaining + alreadyPaid;
    if (paidMinor > obligation) {
      throw ValidationException(
        'Paid amount cannot exceed the current obligation of '
        '${MoneyCalculator.format(obligation)}.',
      );
    }

    final now = DateTime.now();
    await _db.settlementDao.updateById(
      settlementId,
      SettlementsCompanion(
        amountMinor: Value(obligation),
        amountPaidMinor: Value(paidMinor),
        paidAt: Value(paidMinor >= obligation ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deleteById(int id) => _db.settlementDao.deleteById(id);

  Future<SettlementResult> _currentSettlementPlan(int tripId) async {
    final (
      expenseRows,
      shareRows,
      settlementRows,
      paymentRows,
      teamLinkRows,
      teamMemberRows,
    ) = await (
      _db.expenseDao.getByTrip(tripId),
      _db.expenseDao.getSharesByTrip(tripId),
      _db.settlementDao.getByTrip(tripId),
      _db.journeyDao.getPaymentsByTrip(tripId),
      _db.expenseDao.getTeamLinksByTrip(tripId),
      _db.journeyDao.getTeamMembersByTrip(tripId),
    ).wait;

    final allExpenses = expenseRows.map((row) => row.toDomain()).toList();
    final allShares = shareRows.map((row) => row.toDomain()).toList();

    final teamIdsByExpense = <int, List<int>>{};
    for (final link in teamLinkRows) {
      teamIdsByExpense.putIfAbsent(link.expenseId, () => []).add(link.teamId);
    }
    // Enrich expenses with team IDs
    for (var i = 0; i < allExpenses.length; i++) {
      final expense = allExpenses[i];
      if (expense.teamIds.isEmpty && teamIdsByExpense.containsKey(expense.id)) {
        allExpenses[i] = expense.copyWith(
          teamIds: teamIdsByExpense[expense.id] ?? const [],
        );
      }
    }

    // Real team membership (team_members rows), identical to the trip view so
    // record-payment and edit validation always use the same plan that the
    // screens display. An expense-share-derived map would treat every
    // participant of a multi-team expense as a member of every linked team and
    // let cross-team edges leak back in, silently shrinking the pair's
    // outstanding and rejecting valid payments.
    final teamMemberIds = <int, Set<int>>{};
    for (final membership in teamMemberRows) {
      teamMemberIds
          .putIfAbsent(membership.teamId, () => {})
          .add(membership.memberId);
    }

    return SettlementCalculator.calculate(
      expenses: allExpenses,
      shares: allShares,
      settlements: settlementRows.map((row) => row.toDomain()).toList(),
      payments: paymentRows.map((row) => row.toDomain()).toList(),
      teamMemberIds: teamMemberIds.isNotEmpty ? teamMemberIds : null,
    );
  }
}
