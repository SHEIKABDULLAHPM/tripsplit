import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/streams.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';
import '../domain/team_repository.dart';

/// Drift-backed [TeamRepository].
class TeamRepositoryImpl implements TeamRepository {
  TeamRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Team>> watchTeams(int tripId) => _db.journeyDao
      .watchTeams(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<Team>> getTeams(int tripId) async =>
      (await _db.journeyDao.getTeams(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<Team> createTeam(int tripId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('A team needs a name.');
    }
    if (trimmed.length > 80) {
      throw const ValidationException(
        'The team name must be 80 characters or fewer.',
      );
    }
    try {
      final id = await _db.journeyDao.insertTeam(
        TeamsCompanion.insert(tripId: tripId, name: trimmed),
      );
      return Team(id: id, tripId: tripId, name: trimmed);
    } on SqliteException catch (error) {
      if (error.extendedResultCode == 2067) {
        throw ValidationException(
          'A team named "$trimmed" already exists on this trip.',
        );
      }
      throw DatabaseException.fromSqlite(error, table: 'teams');
    }
  }

  @override
  Future<void> renameTeam(int teamId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('A team needs a name.');
    }
    if (trimmed.length > 80) {
      throw const ValidationException(
        'The team name must be 80 characters or fewer.',
      );
    }
    final team = await _db.journeyDao.getTeamById(teamId);
    if (team == null) {
      throw const ValidationException('This team no longer exists.');
    }
    final duplicate = (await _db.journeyDao.getTeams(team.tripId)).any(
      (candidate) =>
          candidate.id != teamId &&
          candidate.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) {
      throw ValidationException(
        'A team named "$trimmed" already exists on this trip.',
      );
    }
    await _db.journeyDao.updateTeam(
      teamId,
      TeamsCompanion(name: Value(trimmed)),
    );
  }

  @override
  Future<void> deleteTeam(int teamId) async {
    final team = await _db.journeyDao.getTeamById(teamId);
    if (team == null) {
      throw const ValidationException('This team no longer exists.');
    }
    final teamExpenses = await _db.expenseDao.byTeam(teamId);
    if (teamExpenses.isNotEmpty) {
      throw const ValidationException(
        'This team has expenses. Reassign the team\'s expenses before '
        'deleting it.',
      );
    }
    await _db.journeyDao.deleteTeam(teamId);
  }

  @override
  Stream<List<Member>> watchTeamMembers(int teamId) {
    late final StreamController<List<Member>> controller;
    StreamSubscription<List<Object?>>? combined;

    controller = StreamController<List<Member>>(
      onListen: () async {
        final team = await _db.journeyDao.getTeamById(teamId);
        if (!controller.hasListener) {
          return;
        }
        if (team == null) {
          controller.add(const []);
          return;
        }
        // Reactively combine team membership with the trip's member rows so that
        // member additions/removals (join-table writes) and member-row changes
        // (renames) both propagate in real time instead of capturing a fixed id
        // list once at subscription time.
        combined =
            combineLatest<Object?>([
              _db.journeyDao.watchTeamMembers(teamId),
              _db.memberDao.watchByTrip(team.tripId),
            ]).listen((values) {
              if (!controller.hasListener) {
                return;
              }
              final memberIds = (values[0] as List<TeamMemberRow>)
                  .map((row) => row.memberId)
                  .toSet();
              final members = (values[1] as List<MemberRow>)
                  .where((row) => memberIds.contains(row.id))
                  .map((row) => row.toDomain())
                  .toList();
              controller.add(members);
            }, onError: controller.addError);
      },
      onCancel: () {
        final subscription = combined;
        combined = null;
        return subscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<List<Member>> getTeamMembers(int teamId) async {
    final memberIds = await _memberIdsOf(teamId);
    if (memberIds.isEmpty) {
      return const [];
    }
    return (await _db.memberDao.getByIds(
      memberIds,
    )).map((row) => row.toDomain()).toList();
  }

  @override
  Future<void> addMember({required int teamId, required int memberId}) async {
    final team = await _db.journeyDao.getTeamById(teamId);
    final member = await _db.memberDao.getById(memberId);
    if (team == null || member == null || team.tripId != member.tripId) {
      throw const ValidationException(
        'A team can only contain members from the same trip.',
      );
    }
    if (await _isInTeam(teamId, memberId)) {
      return;
    }
    try {
      await _db.journeyDao.addTeamMember(teamId, memberId);
    } on SqliteException catch (error) {
      throw DatabaseException.fromSqlite(error, table: 'team_members');
    }
  }

  @override
  Future<void> removeMember({
    required int teamId,
    required int memberId,
  }) async {
    await _db.journeyDao.removeTeamMember(teamId, memberId);
  }

  Future<bool> _isInTeam(int teamId, int memberId) async =>
      (await _db.journeyDao.getTeamMembers(
        teamId,
      )).any((tm) => tm.memberId == memberId);

  Future<List<int>> _memberIdsOf(int teamId) async =>
      (await _db.journeyDao.getTeamMembers(
        teamId,
      )).map((tm) => tm.memberId).toList();
}
