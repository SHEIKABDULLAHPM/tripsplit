import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../../core/calculations/participation.dart';
import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/member.dart';
import '../domain/member_repository.dart';

/// Drift-backed [MemberRepository].
class MemberRepositoryImpl implements MemberRepository {
  MemberRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Member>> watchByTrip(int tripId) => _db.memberDao
      .watchByTrip(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<Member>> getByTrip(int tripId) async =>
      (await _db.memberDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<Member?> findById(int id) async {
    final row = await _db.memberDao.getById(id);
    return row?.toDomain();
  }

  @override
  Future<Member> save(Member member) async {
    final trimmedName = member.name.trim();
    if (member.id > 0) {
      final existing = await _db.memberDao.getById(member.id);
      if (existing == null) {
        throw const ValidationException('This member no longer exists.');
      }
      try {
        await _db.memberDao.updateById(
          member.id,
          MembersCompanion(
            name: Value(trimmedName),
            joinLocationId: Value(member.joinLocationId),
            leaveLocationId: Value(member.leaveLocationId),
          ),
        );
      } on SqliteException catch (error) {
        if (error.extendedResultCode == 2067) {
          throw const ValidationException(
            'A member with this name already exists in the trip.',
          );
        }
        throw DatabaseException.fromSqlite(error, table: 'members');
      }

      final joinChanged =
          existing.joinLocationId != member.joinLocationId ||
          existing.leaveLocationId != member.leaveLocationId;
      if (joinChanged) {
        await _syncJourneyParticipation(member.id);
      }
      return member.copyWith(name: trimmedName);
    }

    int insertedId;
    try {
      insertedId = await _db.memberDao.insert(
        MembersCompanion.insert(
          tripId: member.tripId,
          name: trimmedName,
          joinLocationId: Value(member.joinLocationId),
          leaveLocationId: Value(member.leaveLocationId),
          createdAt: Value(member.createdAt),
        ),
      );
    } on SqliteException catch (error) {
      if (error.extendedResultCode == 2067) {
        throw const ValidationException(
          'A member with this name already exists in the trip.',
        );
      }
      throw DatabaseException.fromSqlite(error, table: 'members');
    }
    return member.copyWith(id: insertedId, name: trimmedName);
  }

  @override
  Future<void> deleteById(int id) async {
    if (await _db.journeyDao.hasPaymentsByMember(id)) {
      throw const ValidationException(
        'This member has paid toward an expense. '
        'Change who paid the expense first.',
      );
    }
    final hasActivity =
        await _db.expenseDao.hasExpensesByPayer(id) ||
        await _db.expenseDao.hasSharesForMember(id) ||
        await _db.settlementDao.hasSettlementsForMember(id);
    if (hasActivity) {
      throw const ValidationException(
        'This member is part of expenses or settlements. '
        'Remove or reassign them first.',
      );
    }

    await _db.transaction(() async {
      await _db.journeyDao.deleteParticipationForMember(id);
      final memberships = await _db.journeyDao.getMembershipsForMembers([id]);
      for (final membership in memberships) {
        await _db.journeyDao.removeTeamMember(membership.teamId, id);
      }
      await _db.memberDao.deleteById(id);
    });
  }

  /// Recomputes stored per-segment participation from the member's join/leave
  /// location, preserving any explicit overrides already present.
  Future<void> _syncJourneyParticipation(int memberId) async {
    final row = await _db.memberDao.getById(memberId);
    if (row == null) {
      return;
    }
    final segments = (await _db.journeyDao.getSegments(
      row.tripId,
    )).map((s) => s.toDomain()).toList();
    if (segments.isEmpty) {
      return;
    }
    final existing = (await _db.journeyDao.getParticipationsForMember(
      memberId,
    )).map((r) => r.toDomain()).toList();
    final derived = ParticipationCalculator.deriveForMember(
      member: row.toDomain(),
      segments: segments,
      existing: existing,
    );

    await _db.journeyDao.deleteParticipationForMember(memberId);
    for (final entry in derived.entries) {
      await _db.journeyDao.upsertParticipation(
        memberId: memberId,
        segmentId: entry.key,
        participating: entry.value,
      );
    }
  }
}
