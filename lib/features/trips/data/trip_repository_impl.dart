import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/trip.dart';
import '../domain/trip_repository.dart';

/// Drift-backed [TripRepository].
class TripRepositoryImpl implements TripRepository {
  TripRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Trip>> watchAll() => _db.tripDao.watchAll().map(
    (rows) => rows.map((row) => row.toDomain()).toList(),
  );

  @override
  Stream<Trip?> watchById(int id) =>
      _db.tripDao.watchById(id).map((row) => row?.toDomain());

  @override
  Future<Trip?> findById(int id) async {
    final row = await _db.tripDao.getById(id);
    return row?.toDomain();
  }

  @override
  Future<void> save(Trip trip) async {
    final entry = _toCompanion(trip);
    try {
      if (trip.id > 0) {
        final updated = await _db.tripDao.updateById(trip.id, entry);
        if (!updated) {
          throw const ValidationException('This trip no longer exists.');
        }
      } else {
        await _db.tripDao.insert(entry);
      }
    } on SqliteException catch (error) {
      if (error.extendedResultCode == 2067) {
        throw const ValidationException(
          'A trip with this name already exists.',
        );
      }
      throw DatabaseException.fromSqlite(error, table: 'trips');
    }
  }

  @override
  Future<void> deleteById(int id) => _db.tripDao.deleteById(id);

  @override
  Future<int> createWithSetup({
    required String name,
    required int budgetMinor,
    required List<NewMemberDraft> members,
    String? startLocation,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ValidationException('Trip name is required.');
    }
    if (budgetMinor < 0) {
      throw const ValidationException('Budget cannot be negative.');
    }
    for (final draft in members) {
      if (draft.contributionMinor < 0) {
        throw ValidationException(
          'Contribution for ${draft.name.trim()} cannot be negative.',
        );
      }
    }

    final now = DateTime.now();

    return _db.transaction(() async {
      final tripId = await _insertTrip(
        trimmedName,
        budgetMinor,
        now,
        startLocation?.trim(),
        startDate,
        endDate,
      );

      for (final draft in members) {
        final trimmedName = draft.name.trim();
        int memberId;
        try {
          memberId = await _db.memberDao.insert(
            MembersCompanion.insert(
              tripId: tripId,
              name: trimmedName,
              createdAt: Value(now),
            ),
          );
        } on SqliteException catch (error) {
          if (error.extendedResultCode == 2067) {
            throw ValidationException(
              'A member named $trimmedName already exists in this trip.',
            );
          }
          throw DatabaseException.fromSqlite(error, table: 'members');
        }
        if (draft.contributionMinor > 0) {
          await _db.contributionDao.insert(
            ContributionsCompanion.insert(
              tripId: tripId,
              memberId: memberId,
              amountMinor: Value(draft.contributionMinor),
              createdAt: Value(now),
            ),
          );
        }
      }

      return tripId;
    });
  }

  Future<int> _insertTrip(
    String name,
    int budgetMinor,
    DateTime now,
    String? startLocation,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      return await _db.tripDao.insert(
        TripsCompanion.insert(
          name: name,
          totalBudgetMinor: Value(budgetMinor),
          startLocation: Value(startLocation),
          startDate: Value(startDate),
          endDate: Value(endDate),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    } on SqliteException catch (error) {
      if (error.extendedResultCode == 2067) {
        throw const ValidationException(
          'A trip with this name already exists.',
        );
      }
      throw DatabaseException.fromSqlite(error, table: 'trips');
    }
  }

  static TripsCompanion _toCompanion(Trip trip) => TripsCompanion(
    id: trip.id > 0 ? Value(trip.id) : const Value.absent(),
    name: Value(trip.name),
    description: Value(trip.description),
    currencyCode: Value(trip.currencyCode),
    startDate: Value(trip.startDate),
    endDate: Value(trip.endDate),
    startLocation: Value(trip.startLocation),
    totalBudgetMinor: Value(trip.totalBudgetMinor),
    createdAt: Value(trip.createdAt),
    updatedAt: Value(trip.updatedAt),
  );
}
