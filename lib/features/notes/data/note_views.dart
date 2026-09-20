import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../injection/database_providers.dart';
import '../domain/note.dart';

/// Reactive list of notes belonging to a single trip.
final notesForTripProvider = StreamProvider.autoDispose.family<List<Note>, int>(
  (ref, tripId) => ref.watch(noteRepositoryProvider).watchByTrip(tripId),
);
