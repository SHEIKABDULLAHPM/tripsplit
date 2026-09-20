import 'package:drift/drift.dart';

import '../../../core/calculations/expense_split.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/streams.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/expense.dart';
import '../domain/expense_payment.dart';
import '../domain/expense_repository.dart';
import '../domain/expense_scope.dart';
import '../domain/expense_share.dart';

/// Drift-backed [ExpenseRepository].
///
/// Expenses, their shares and their payments are always written inside a
/// transaction so the invariants "shares sum exactly to the shareable expense
/// total" and "payments sum exactly to the full expense amount" can never be
/// broken, even when part of the write fails.
class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl(this._db);

  final AppDatabase _db;
  final ExpenseSplitter _splitter = const EqualExpenseSplitter();

  @override
  Stream<List<Expense>> watchByTrip(int tripId) =>
      mapLatest<Object?, List<Expense>>(
        [
          _db.expenseDao.watchByTrip(tripId),
          _db.expenseDao.watchTeamLinksByTrip(tripId),
        ],
        (values) => _hydrateTeamIds(
          values[0] as List<ExpenseRow>,
          values[1] as List<ExpenseTeamRow>,
        ),
      );

  @override
  Stream<Expense?> watchById(int id) => mapLatest<Object?, Expense?>(
    [_db.expenseDao.watchById(id), _db.expenseDao.watchTeamLinksFor(id)],
    (values) {
      final row = values[0] as ExpenseRow?;
      if (row == null) {
        return null;
      }
      final links = values[1] as List<ExpenseTeamRow>;
      return row.toDomain().copyWith(
        teamIds: [for (final link in links) link.teamId],
      );
    },
  );

  @override
  Future<List<Expense>> getByTrip(int tripId) async {
    final rows = await _db.expenseDao.getByTrip(tripId);
    final links = await _db.expenseDao.getTeamLinksByTrip(tripId);
    return _hydrateTeamIds(rows, links);
  }

  @override
  Future<Expense?> getById(int id) async {
    final row = await _db.expenseDao.getById(id);
    if (row == null) return null;
    final links = await _db.expenseDao.getTeamLinksFor(id);
    return row.toDomain().copyWith(
      teamIds: [for (final link in links) link.teamId],
    );
  }

  List<Expense> _hydrateTeamIds(
    List<ExpenseRow> rows,
    List<ExpenseTeamRow> links,
  ) {
    final teamIdsByExpense = <int, List<int>>{};
    for (final link in links) {
      teamIdsByExpense
          .putIfAbsent(link.expenseId, () => <int>[])
          .add(link.teamId);
    }
    return [
      for (final row in rows)
        row.toDomain().copyWith(teamIds: teamIdsByExpense[row.id] ?? const []),
    ];
  }

  @override
  Future<List<ExpenseShare>> getSharesFor(int expenseId) async =>
      (await _db.expenseDao.getSharesFor(
        expenseId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<List<ExpensePayment>> getPaymentsFor(int expenseId) async =>
      (await _db.journeyDao.getPaymentsFor(
        expenseId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<void> createExpense({
    required int tripId,
    required String description,
    required int amountMinor,
    int externalAmountMinor = 0,
    required int payerMemberId,
    ExpenseScope scope = ExpenseScope.shared,
    int? segmentId,
    int? teamId,
    List<int> teamIds = const [],
    int? payerTeamId,
    String? category,
    DateTime? spentAt,
    List<int> participantMemberIds = const [],
    List<ExpensePayment> otherPayers = const [],
    Map<int, int> customShares = const {},
  }) async {
    final effectiveTeamIds = _resolveTeamIds(teamIds: teamIds, teamId: teamId);
    final legacyTeamId =
        teamId ?? (effectiveTeamIds.isNotEmpty ? effectiveTeamIds.first : null);
    final resolvedPayerTeamId =
        scope == ExpenseScope.team &&
            payerTeamId == null &&
            effectiveTeamIds.isNotEmpty
        ? effectiveTeamIds.first
        : payerTeamId;
    _validateInput(
      description: description,
      amountMinor: amountMinor,
      externalAmountMinor: externalAmountMinor,
      otherPayers: otherPayers,
    );
    await _validateMembers(
      tripId: tripId,
      payerMemberId: payerMemberId,
      participants: participantMemberIds,
      otherPayers: otherPayers,
    );
    await _validateScope(
      tripId: tripId,
      scope: scope,
      segmentId: segmentId,
      teamIds: effectiveTeamIds,
    );
    await _validateTeamPayers(
      teamIds: effectiveTeamIds,
      payerMemberId: payerMemberId,
      payerTeamId: resolvedPayerTeamId,
      otherPayers: otherPayers,
    );
    if (scope == ExpenseScope.custom) {
      await _validateCustomShares(
        customShares: customShares,
        participantMemberIds: participantMemberIds,
        totalMinor: amountMinor - externalAmountMinor,
      );
    }

    final now = DateTime.now();
    final shares = scope == ExpenseScope.custom && customShares.isNotEmpty
        ? customShares.entries
              .map((e) => MemberShare(memberId: e.key, amountMinor: e.value))
              .toList()
        : _splitter.split(
            totalMinor: amountMinor - externalAmountMinor,
            memberIds: participantMemberIds,
          );
    final payments = _buildPayments(
      payerMemberId: payerMemberId,
      amountMinor: amountMinor,
      otherPayers: otherPayers,
      payerTeamId: resolvedPayerTeamId,
    );

    await _db.transaction(() async {
      final expenseId = await _db.expenseDao.insert(
        ExpensesCompanion.insert(
          tripId: tripId,
          payerMemberId: payerMemberId,
          description: description.trim(),
          scope: Value(scope.apiValue),
          segmentId: Value(segmentId),
          teamId: Value(legacyTeamId),
          amountMinor: Value(amountMinor),
          externalAmountMinor: Value(externalAmountMinor),
          category: Value(category),
          spentAt: Value(spentAt),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await _db.expenseDao.insertTeamLinks(expenseId, effectiveTeamIds);
      await _insertShares(expenseId, shares);
      await _insertPayments(expenseId, payments);
    });
  }

  @override
  Future<void> updateExpense({
    required int expenseId,
    required String description,
    required int amountMinor,
    int externalAmountMinor = 0,
    required int payerMemberId,
    ExpenseScope scope = ExpenseScope.shared,
    int? segmentId,
    int? teamId,
    List<int> teamIds = const [],
    int? payerTeamId,
    String? category,
    DateTime? spentAt,
    List<int> participantMemberIds = const [],
    List<ExpensePayment> otherPayers = const [],
    Map<int, int> customShares = const {},
  }) async {
    final existing = await _db.expenseDao.getById(expenseId);
    if (existing == null) {
      throw const ValidationException('This expense no longer exists.');
    }
    final effectiveTeamIds = _resolveTeamIds(teamIds: teamIds, teamId: teamId);
    final legacyTeamId =
        teamId ?? (effectiveTeamIds.isNotEmpty ? effectiveTeamIds.first : null);
    final resolvedPayerTeamId =
        scope == ExpenseScope.team &&
            payerTeamId == null &&
            effectiveTeamIds.isNotEmpty
        ? effectiveTeamIds.first
        : payerTeamId;
    _validateInput(
      description: description,
      amountMinor: amountMinor,
      externalAmountMinor: externalAmountMinor,
      otherPayers: otherPayers,
    );
    await _validateMembers(
      tripId: existing.tripId,
      payerMemberId: payerMemberId,
      participants: participantMemberIds,
      otherPayers: otherPayers,
    );
    await _validateScope(
      tripId: existing.tripId,
      scope: scope,
      segmentId: segmentId,
      teamIds: effectiveTeamIds,
    );
    await _validateTeamPayers(
      teamIds: effectiveTeamIds,
      payerMemberId: payerMemberId,
      payerTeamId: resolvedPayerTeamId,
      otherPayers: otherPayers,
    );
    if (scope == ExpenseScope.custom) {
      await _validateCustomShares(
        customShares: customShares,
        participantMemberIds: participantMemberIds,
        totalMinor: amountMinor - externalAmountMinor,
      );
    }

    final now = DateTime.now();
    final shares = scope == ExpenseScope.custom && customShares.isNotEmpty
        ? customShares.entries
              .map((e) => MemberShare(memberId: e.key, amountMinor: e.value))
              .toList()
        : _splitter.split(
            totalMinor: amountMinor - externalAmountMinor,
            memberIds: participantMemberIds,
          );
    final payments = _buildPayments(
      payerMemberId: payerMemberId,
      amountMinor: amountMinor,
      otherPayers: otherPayers,
      payerTeamId: resolvedPayerTeamId,
    );

    await _db.transaction(() async {
      await _db.expenseDao.updateById(
        expenseId,
        ExpensesCompanion(
          description: Value(description.trim()),
          amountMinor: Value(amountMinor),
          externalAmountMinor: Value(externalAmountMinor),
          payerMemberId: Value(payerMemberId),
          scope: Value(scope.apiValue),
          segmentId: Value(segmentId),
          teamId: Value(legacyTeamId),
          category: Value(category),
          spentAt: Value(spentAt),
          updatedAt: Value(now),
        ),
      );

      await _db.expenseDao.deleteSharesFor(expenseId);
      await _db.journeyDao.deletePaymentsFor(expenseId);
      await _db.expenseDao.deleteTeamLinksFor(expenseId);
      await _db.expenseDao.insertTeamLinks(expenseId, effectiveTeamIds);

      await _insertShares(expenseId, shares);
      await _insertPayments(expenseId, payments);
    });
  }

  @override
  Future<void> deleteExpense({
    required int tripId,
    required int expenseId,
  }) async {
    final existing = await _db.expenseDao.getById(expenseId);
    if (existing == null || existing.tripId != tripId) {
      throw const ValidationException('This expense no longer exists.');
    }

    await _db.transaction(() async {
      await _db.journeyDao.deletePaymentsFor(expenseId);
      await _db.expenseDao.deleteSharesFor(expenseId);
      await _db.expenseDao.deleteTeamLinksFor(expenseId);
      await _db.expenseDao.deleteById(expenseId);
    });
  }

  Future<void> _insertShares(int expenseId, List<MemberShare> shares) async {
    for (final share in shares) {
      await _db.expenseDao.insertShare(
        ExpenseSharesCompanion.insert(
          expenseId: expenseId,
          memberId: share.memberId,
          shareMinor: Value(share.amountMinor),
        ),
      );
    }
  }

  Future<void> _insertPayments(
    int expenseId,
    List<ExpensePayment> payments,
  ) async {
    for (final payment in payments) {
      await _db.journeyDao.insertPayment(
        ExpensePaymentsCompanion.insert(
          expenseId: expenseId,
          memberId: payment.memberId,
          amountMinor: Value(payment.amountMinor),
          teamId: Value(payment.teamId),
        ),
      );
    }
  }

  /// Builds the authoritative payment rows for an expense.
  ///
  /// When no other payers exist the primary payer is recorded as paying the
  /// full amount (identical to the historical model). Otherwise the primary
  /// pays the remainder after the other payers' amounts.
  List<ExpensePayment> _buildPayments({
    required int payerMemberId,
    required int amountMinor,
    required List<ExpensePayment> otherPayers,
    int? payerTeamId,
  }) {
    if (otherPayers.isEmpty) {
      return [
        ExpensePayment(
          id: 0,
          expenseId: 0,
          memberId: payerMemberId,
          amountMinor: amountMinor,
          teamId: payerTeamId,
        ),
      ];
    }
    final othersTotal = otherPayers.fold<int>(
      0,
      (sum, p) => sum + p.amountMinor,
    );
    final primary = amountMinor - othersTotal;
    return [
      ExpensePayment(
        id: 0,
        expenseId: 0,
        memberId: payerMemberId,
        amountMinor: primary,
        teamId: payerTeamId,
      ),
      for (final other in otherPayers)
        ExpensePayment(
          id: 0,
          expenseId: 0,
          memberId: other.memberId,
          amountMinor: other.amountMinor,
          teamId: other.teamId,
        ),
    ];
  }

  /// Resolves the authoritative team set. New callers pass [teamIds]
  /// (join rows); legacy callers still pass a single [teamId], which implies
  /// `[teamId]`.
  static List<int> _resolveTeamIds({
    required List<int> teamIds,
    required int? teamId,
  }) => teamIds.isNotEmpty ? teamIds : (teamId != null ? [teamId] : const []);

  static void _validateInput({
    required String description,
    required int amountMinor,
    required int externalAmountMinor,
    required List<ExpensePayment> otherPayers,
  }) {
    if (description.trim().isEmpty) {
      throw const ValidationException('An expense needs a description.');
    }
    if (description.trim().length > 200) {
      throw const ValidationException(
        'The description must be 200 characters or fewer.',
      );
    }
    if (amountMinor <= 0) {
      throw const ValidationException(
        'Expense amount must be greater than zero.',
      );
    }
    if (externalAmountMinor < 0) {
      throw const ValidationException(
        'The external portion cannot be negative.',
      );
    }
    if (externalAmountMinor >= amountMinor) {
      throw const ValidationException(
        'The external portion must be smaller than the expense amount, so '
        'that at least some of the expense is shared with the group.',
      );
    }
    for (final payer in otherPayers) {
      if (payer.amountMinor <= 0) {
        throw const ValidationException(
          'A comparison payer amount must be greater than zero.',
        );
      }
      if (payer.memberId <= 0) {
        throw const ValidationException('Every payer must be a trip member.');
      }
    }
    final othersTotal = otherPayers.fold<int>(
      0,
      (sum, p) => sum + p.amountMinor,
    );
    if (othersTotal >= amountMinor) {
      throw const ValidationException(
        'Other payers together cannot cover the entire expense; the primary '
        'payer must pay at least part of it.',
      );
    }
    // The external (non-group) portion is attributed to the primary payer, so
    // it must not exceed what the primary payer actually paid.
    final primaryPortion = amountMinor - othersTotal;
    if (externalAmountMinor > primaryPortion) {
      throw const ValidationException(
        'The external portion cannot exceed what the primary payer paid '
        'toward this expense.',
      );
    }
  }

  Future<void> _validateMembers({
    required int tripId,
    required int payerMemberId,
    required List<int> participants,
    required List<ExpensePayment> otherPayers,
  }) async {
    if (participants.isEmpty) {
      throw const ValidationException('Select at least one participant.');
    }
    if (participants.toSet().length != participants.length) {
      throw const ValidationException(
        'Each participant can be listed only once.',
      );
    }

    final memberIds = (await _db.memberDao.getByTrip(
      tripId,
    )).map((m) => m.id).toSet();
    if (!memberIds.contains(payerMemberId)) {
      throw const ValidationException(
        'The payer must be a member of this trip.',
      );
    }
    if (!participants.toSet().every(memberIds.contains)) {
      throw const ValidationException(
        'All participants must be members of this trip.',
      );
    }
    for (final payer in otherPayers) {
      if (payer.memberId == payerMemberId) {
        throw const ValidationException(
          'The primary payer should not also be listed as another payer.',
        );
      }
      if (!memberIds.contains(payer.memberId)) {
        throw const ValidationException(
          'Every payer must be a member of this trip.',
        );
      }
    }
  }

  Future<void> _validateScope({
    required int tripId,
    required ExpenseScope scope,
    required int? segmentId,
    required List<int> teamIds,
  }) async {
    if (scope == ExpenseScope.team && teamIds.isEmpty) {
      throw const ValidationException(
        'A team expense needs at least one team selected.',
      );
    }
    if (scope == ExpenseScope.segment && segmentId == null) {
      throw const ValidationException(
        'A segment expense needs a travel segment selected.',
      );
    }
    if (teamIds.isNotEmpty && scope == ExpenseScope.segment) {
      throw const ValidationException(
        'A segment expense cannot also apply to a team.',
      );
    }
    if (teamIds.isNotEmpty && scope != ExpenseScope.team) {
      throw const ValidationException(
        'Teams can only apply to team-scoped expenses.',
      );
    }
    if (teamIds.toSet().length != teamIds.length) {
      throw const ValidationException('Each team can be selected only once.');
    }
    for (final teamId in teamIds) {
      final team = await _db.journeyDao.getTeamById(teamId);
      if (team == null || team.tripId != tripId) {
        throw const ValidationException('Every team must belong to this trip.');
      }
    }
    if (segmentId != null) {
      final segment = await _db.journeyDao.getSegmentById(segmentId);
      if (segment == null || segment.tripId != tripId) {
        throw const ValidationException(
          'The travel segment must belong to this trip.',
        );
      }
    }
  }

  /// Validates the payer→team attribution rules.
  ///
  /// Any payer (primary or otherwise) that records a [teamId] must pay on
  /// behalf of one of the expense's own teams. Cross-team payments are
  /// allowed — a payer does not need to be a member of the team they are
  /// paying on behalf of. A team may have no payer at all — it is then
  /// simply covered by another team's payer.
  Future<void> _validateTeamPayers({
    required List<int> teamIds,
    required int payerMemberId,
    required int? payerTeamId,
    required List<ExpensePayment> otherPayers,
  }) async {
    final teams = teamIds.toSet();
    if (payerTeamId != null && !teams.contains(payerTeamId)) {
      throw const ValidationException(
        'The payer team must be one of the expense\'s teams.',
      );
    }
    for (final payer in otherPayers) {
      if (payer.teamId != null && !teams.contains(payer.teamId)) {
        throw const ValidationException(
          'Each payer team must be one of the expense\'s teams.',
        );
      }
    }
  }

  Future<void> _validateCustomShares({
    required Map<int, int> customShares,
    required List<int> participantMemberIds,
    required int totalMinor,
  }) async {
    if (customShares.isEmpty) {
      throw const ValidationException(
        'Set a share amount for each participant.',
      );
    }
    final participants = participantMemberIds.toSet();
    if (!participants.every(customShares.containsKey)) {
      throw const ValidationException(
        'Custom shares must cover all participants.',
      );
    }
    if (!customShares.keys.every(participants.contains)) {
      throw const ValidationException(
        'Custom shares cannot include someone who is not participating.',
      );
    }
    for (final share in customShares.values) {
      if (share <= 0) {
        throw const ValidationException(
          'Each participant share must be more than zero.',
        );
      }
    }
    final total = customShares.values.fold<int>(0, (sum, v) => sum + v);
    if (total != totalMinor) {
      throw ValidationException(
        'Custom shares must sum to ${MoneyCalculator.format(totalMinor)}.',
      );
    }
  }
}
