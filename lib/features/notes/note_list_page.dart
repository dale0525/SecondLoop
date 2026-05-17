import 'package:flutter/material.dart';

import '../../core/offline_edit/local_edit_models.dart';

class NoteListEntry {
  const NoteListEntry({
    required this.id,
    required this.title,
    required this.updatedAtMs,
    this.bodyPreview = '',
    this.syncState = LocalEditSyncState.clean,
  });

  final String id;
  final String title;
  final String bodyPreview;
  final int updatedAtMs;
  final LocalEditSyncState syncState;
}

class NoteListPage extends StatefulWidget {
  const NoteListPage({
    required this.entries,
    super.key,
    this.onOpenNote,
  });

  final List<NoteListEntry> entries;
  final ValueChanged<NoteListEntry>? onOpenNote;

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
      appBar: AppBar(title: const Text('Notes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('note_list_search_field'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search',
                    border: OutlineInputBorder(),
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
              title: Text(entry.title.isEmpty ? 'Untitled' : entry.title),
              subtitle: Text(entry.bodyPreview),
              trailing: _NoteSyncBadge(state: entry.syncState),
              onTap: widget.onOpenNote == null
                  ? null
                  : () => widget.onOpenNote!(entry),
            ),
        ],
      ),
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
      LocalEditSyncState.pending => 'Pending',
      LocalEditSyncState.syncing => 'Saving',
      LocalEditSyncState.conflict => 'Conflict',
      LocalEditSyncState.failed => 'Failed',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Chip(label: Text(label));
  }
}
