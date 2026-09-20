import 'package:drift/drift.dart';

import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';

/// Drift-backed [NoteRepository].
class NoteRepositoryImpl implements NoteRepository {
  NoteRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Note>> watchByTrip(int tripId) => _db.noteDao
      .watchByTrip(tripId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  @override
  Future<void> save(Note note) async {
    final now = DateTime.now();
    final title = note.title.trim().isEmpty
        ? 'Untitled note'
        : note.title.trim();
    if (note.id > 0) {
      final updated = await _db.noteDao.updateById(
        note.id,
        NotesCompanion(
          title: Value(title),
          body: Value(note.body),
          updatedAt: Value(now),
        ),
      );
      if (!updated) {
        throw const ValidationException('This note no longer exists.');
      }
      return;
    }
    await _db.noteDao.insert(
      NotesCompanion.insert(
        tripId: note.tripId,
        title: title,
        body: Value(note.body),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deleteById(int id) => _db.noteDao.deleteById(id);
}
