import 'package:freezed_annotation/freezed_annotation.dart';
part 'note.freezed.dart';
part 'note.g.dart';

/// Immutable domain entity representing a note attached to a trip.
///
/// This is the pure-Dart representation used across the domain and
/// presentation layers. Persistence mapping to the database row is handled in
/// the data layer.
@freezed
sealed class Note with _$Note {
  const factory Note({
    required int id,
    required int tripId,
    required String title,
    @Default('') String body,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}
