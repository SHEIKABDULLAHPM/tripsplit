import 'note.dart';

/// Abstract contract for persisting [Note] entities.
///
/// Implementations live in the data layer; the domain and presentation layers
/// depend only on this interface.
abstract interface class NoteRepository {
  Stream<List<Note>> watchByTrip(int tripId);

  /// Inserts a new note or updates an existing one (id > 0).
  Future<void> save(Note note);
  Future<void> deleteById(int id);
}
