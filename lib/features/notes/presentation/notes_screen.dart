import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../injection/database_providers.dart';
import '../data/note_views.dart';
import '../domain/note.dart';

/// Notes screen: quick note experience, no title popup required.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key, required this.tripId});

  final int tripId;

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createQuickNote(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QuickNoteEditor()));
    if (result == null || result.trim().isEmpty || !context.mounted) return;
    final now = DateTime.now();
    // Auto-generate title from first sentence
    final body = result.trim();
    final title = _autoTitle(body);
    try {
      await ref
          .read(noteRepositoryProvider)
          .save(
            Note(
              id: 0,
              tripId: tripId,
              title: title,
              body: body,
              createdAt: now,
              updatedAt: now,
            ),
          );
    } on AppException catch (e) {
      if (context.mounted) _showSnack(context, e.message);
    }
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref, Note note) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _QuickNoteEditor(initialText: note.body),
      ),
    );
    if (result == null || result.trim().isEmpty || !context.mounted) return;
    final body = result.trim();
    final title = _autoTitle(body);
    try {
      await ref
          .read(noteRepositoryProvider)
          .save(
            Note(
              id: note.id,
              tripId: tripId,
              title: title,
              body: body,
              createdAt: note.createdAt,
              updatedAt: DateTime.now(),
            ),
          );
    } on AppException catch (e) {
      if (context.mounted) _showSnack(context, e.message);
    }
  }

  Future<void> _deleteNote(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(noteRepositoryProvider).deleteById(note.id);
    } on AppException catch (e) {
      if (context.mounted) _showSnack(context, e.message);
    }
  }

  /// Auto-generate title from the first sentence of the note body.
  static String _autoTitle(String body) {
    if (body.isEmpty) return 'Untitled note';
    // Take first sentence (up to first period, exclamation, newline, or
    // 80 chars).
    final patterns = [RegExp(r'[.!?\n]')];
    var end = body.length;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null && match.start < end && match.start > 0) {
        end = match.start;
      }
    }
    final title = body.substring(0, end.clamp(0, 80)).trim();
    return title.isEmpty ? 'Untitled note' : title;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesForTripProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-note-fab',
        onPressed: () => _createQuickNote(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Quick note'),
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<List<Note>>(
          value: notes,
          onRetry: () => ref.invalidate(notesForTripProvider(tripId)),
          isEmpty: (items) => items.isEmpty,
          empty: const EmptyState(
            icon: Icons.sticky_note_2_outlined,
            title: 'No notes yet',
            message:
                'Tap "Quick note" to capture a reminder, address, or trip detail.',
          ),
          builder: (items) => ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              88,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final note = items[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xxs,
                  ),
                  title: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: note.body.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            note.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMuted,
                          ),
                        ),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _deleteNote(context, ref, note),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                  onTap: () => _editNote(context, ref, note),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Full-screen quick note editor — no title popup, just start typing.
class _QuickNoteEditor extends StatefulWidget {
  const _QuickNoteEditor({this.initialText});
  final String? initialText;

  @override
  State<_QuickNoteEditor> createState() => _QuickNoteEditorState();
}

class _QuickNoteEditorState extends State<_QuickNoteEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick note'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(
              'Save',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Start typing your note...',
              border: InputBorder.none,
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
