import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/contribution.dart';
import '../domain/contribution_repository.dart';

/// Drift-backed [ContributionRepository].
class ContributionRepositoryImpl implements ContributionRepository {
  ContributionRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Contribution>> watchByTrip(int tripId) => _db.contributionDao
      .watchByTrip(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<List<Contribution>> getByTrip(int tripId) async =>
      (await _db.contributionDao.getByTrip(
        tripId,
      )).map((row) => row.toDomain()).toList();

  @override
  Future<void> save(Contribution contribution) async {
    if (contribution.amountMinor <= 0) {
      throw const ValidationException(
        'Contribution must be greater than zero.',
      );
    }
    final member = await _db.memberDao.getById(contribution.memberId);
    if (member == null || member.tripId != contribution.tripId) {
      throw const ValidationException(
        'The contribution member must belong to the selected trip.',
      );
    }
    if (contribution.id > 0) {
      final existing = await _db.contributionDao.getById(contribution.id);
      if (existing == null || existing.tripId != contribution.tripId) {
        throw const ValidationException('This contribution no longer exists.');
      }
      final updated = await _db.contributionDao.updateById(
        contribution.id,
        ContributionsCompanion(
          amountMinor: Value(contribution.amountMinor),
          note: Value(contribution.note),
        ),
      );
      if (!updated) {
        throw const ValidationException(
          'This contribution could not be updated.',
        );
      }
      return;
    }

    try {
      await _db.contributionDao.insert(
        ContributionsCompanion.insert(
          tripId: contribution.tripId,
          memberId: contribution.memberId,
          amountMinor: Value(contribution.amountMinor),
          note: Value(contribution.note),
          createdAt: Value(contribution.createdAt),
        ),
      );
    } on SqliteException catch (error) {
      throw DatabaseException.fromSqlite(error, table: 'contributions');
    }
  }

  @override
  Future<void> deleteById(int id) => _db.contributionDao.deleteById(id);
}
