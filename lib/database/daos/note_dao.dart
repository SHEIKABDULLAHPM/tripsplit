import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/notes.dart';
part 'note_dao.g.dart';

/// Low-level data access for trip notes.
///
/// Notes belong to a single trip and are deleted automatically when their
/// trip is removed (foreign-key cascade).
@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  Stream<List<NoteRow>> watchByTrip(int tripId) =>
      (select(notes)
            ..where((n) => n.tripId.equals(tripId))
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .watch();

  Future<List<NoteRow>> getByTrip(int tripId) =>
      (select(notes)
            ..where((n) => n.tripId.equals(tripId))
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .get();

  Future<int> insert(NotesCompanion entry) => into(notes).insert(entry);

  Future<bool> updateById(int id, NotesCompanion entry) async =>
      (await (update(notes)..where((n) => n.id.equals(id))).write(entry)) == 1;

  Future<int> deleteById(int id) =>
      (delete(notes)..where((n) => n.id.equals(id))).go();
}
