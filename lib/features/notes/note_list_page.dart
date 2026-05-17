import 'package:flutter/material.dart';

import '../../core/cloud/runtime_note_client.dart';
import '../../core/offline_edit/local_edit_models.dart';
import '../../i18n/strings.g.dart';

typedef NoteListDeleteCallback = Future<void> Function(NoteListEntry entry);

class NoteListEntry {
  const NoteListEntry({
    required this.id,
    required this.title,
    required this.updatedAtMs,
    this.bodyPreview = '',
    this.syncState = LocalEditSyncState.clean,
    this.baseRevision,
  });

  final String id;
  final String title;
  final String bodyPreview;
  final int updatedAtMs;
  final LocalEditSyncState syncState;
  final String? baseRevision;
}

class NoteListPage extends StatefulWidget {
  const NoteListPage({
    required this.entries,
    super.key,
    this.onOpenNote,
    this.onCreateNote,
    this.onDeleteNote,
  });

  final List<NoteListEntry> entries;
  final ValueChanged<NoteListEntry>? onOpenNote;
  final VoidCallback? onCreateNote;
  final NoteListDeleteCallback? onDeleteNote;

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  final _searchController = TextEditingController();
  var _sortNewestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final entries = widget.entries
        .where(
          (entry) =>
              query.isEmpty ||
              entry.title.toLowerCase().contains(query) ||
              entry.bodyPreview.toLowerCase().contains(query),
        )
        .toList()
      ..sort((a, b) {
        final result = b.updatedAtMs.compareTo(a.updatedAtMs);
        return _sortNewestFirst ? result : -result;
      });

    return Scaffold(
      appBar: AppBar(title: Text(context.t.notes.title)),
      floatingActionButton: widget.onCreateNote == null
          ? null
          : FloatingActionButton(
              key: const ValueKey('note_list_create_button'),
              onPressed: widget.onCreateNote,
              child: const Icon(Icons.add),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('note_list_search_field'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.t.notes.fields.search,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.arrow_upward),
                  ),
                ],
                selected: {_sortNewestFirst},
                onSelectionChanged: (value) {
                  setState(() => _sortNewestFirst = value.single);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in entries)
            ListTile(
              key: ValueKey('note_list_item_${entry.id}'),
              title: Text(
                entry.title.isEmpty
                    ? context.t.notes.labels.untitled
                    : entry.title,
              ),
              subtitle: Text(entry.bodyPreview),
              trailing: _NoteListItemActions(
                entry: entry,
                onDeleteNote: widget.onDeleteNote,
              ),
              onTap: widget.onOpenNote == null
                  ? null
                  : () => widget.onOpenNote!(entry),
            ),
        ],
      ),
    );
  }
}

class _NoteListItemActions extends StatelessWidget {
  const _NoteListItemActions({
    required this.entry,
    required this.onDeleteNote,
  });

  final NoteListEntry entry;
  final NoteListDeleteCallback? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    final delete = onDeleteNote;
    if (delete == null) {
      return _NoteSyncBadge(state: entry.syncState);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NoteSyncBadge(state: entry.syncState),
        IconButton(
          key: ValueKey('note_list_delete_${entry.id}'),
          tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await delete(entry);
          },
        ),
      ],
    );
  }
}

class _NoteSyncBadge extends StatelessWidget {
  const _NoteSyncBadge({required this.state});

  final LocalEditSyncState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      LocalEditSyncState.clean => '',
      LocalEditSyncState.pending => context.t.notes.status.pending,
      LocalEditSyncState.syncing => context.t.notes.status.saving,
      LocalEditSyncState.conflict => context.t.notes.status.conflict,
      LocalEditSyncState.failed => context.t.notes.status.failed,
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Chip(label: Text(label));
  }
}

List<NoteListEntry> mergeNoteListEntries(
  List<RuntimeNote> remoteNotes,
  List<LocalTextEdit> localEdits,
) {
  final entriesById = <String, NoteListEntry>{};
  for (final note in remoteNotes) {
    entriesById[note.id] = NoteListEntry(
      id: note.id,
      title: note.title,
      bodyPreview: _preview(note.body),
      updatedAtMs: note.updatedAtMs,
      syncState: LocalEditSyncState.clean,
      baseRevision: note.revision,
    );
  }
  for (final edit in localEdits) {
    final id = edit.remoteId ?? edit.localId;
    entriesById[id] = NoteListEntry(
      id: id,
      title: edit.title,
      bodyPreview: _preview(edit.body),
      updatedAtMs: edit.updatedAtMs,
      syncState: edit.syncState,
      baseRevision: edit.baseRevision,
    );
  }
  return entriesById.values.toList(growable: false)
    ..sort((left, right) {
      final byUpdated = right.updatedAtMs.compareTo(left.updatedAtMs);
      if (byUpdated != 0) return byUpdated;
      return left.id.compareTo(right.id);
    });
}

String _preview(String body) {
  final normalized = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 120) return normalized;
  return '${normalized.substring(0, 120)}...';
}
