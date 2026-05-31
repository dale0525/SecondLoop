import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell_style.dart';
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
        if (result != 0) return result;
        return a.id.compareTo(b.id);
      });
    final visibleItems = _recentItemsForEntries(context, entries);
    final showVaultTopBar =
        AppShellLayoutScope.desktopWorkbenchOf(context) != true;

    return Material(
      color: _VaultColors.surface,
      child: Column(
        children: [
          if (showVaultTopBar)
            _VaultTopBar(
              title: context.t.notes.vault.brand,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 84),
              children: [
                _VaultSearchHeader(
                  controller: _searchController,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 32),
                _VaultCategoryGrid(
                  notesCount: widget.entries.isEmpty
                      ? context.t.notes.vault.categories.notesSampleCount
                      : context.t.notes.vault.categories
                          .notesCount(count: widget.entries.length),
                  onOpenNotes: widget.onCreateNote,
                ),
                const SizedBox(height: 40),
                _VaultRecentSection(
                  items: visibleItems,
                  showFallback: entries.isEmpty && query.isEmpty,
                  onViewAll: widget.onCreateNote,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_VaultRecentItem> _recentItemsForEntries(
    BuildContext context,
    List<NoteListEntry> entries,
  ) {
    if (entries.isEmpty) return const <_VaultRecentItem>[];
    return entries.take(2).map((entry) {
      final title =
          entry.title.isEmpty ? context.t.notes.labels.untitled : entry.title;
      return _VaultRecentItem(
        id: entry.id,
        title: title,
        icon: Icons.edit_note,
        color: _VaultColors.onSurface,
        onTap:
            widget.onOpenNote == null ? null : () => widget.onOpenNote!(entry),
        onDelete: widget.onDeleteNote == null
            ? null
            : () => widget.onDeleteNote!(entry),
      );
    }).toList(growable: false);
  }
}

class _VaultTopBar extends StatelessWidget {
  const _VaultTopBar({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _VaultColors.surface,
        border: Border(
          bottom: BorderSide(color: _VaultColors.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const _VaultAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _VaultColors.onSurface,
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                tooltip: context.t.notes.vault.notifications,
                icon: const Icon(
                  Icons.notifications_none,
                  size: 20,
                  color: _VaultColors.onSurfaceVariant,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultAvatar extends StatelessWidget {
  const _VaultAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _VaultColors.outlineVariant),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFE8E2D7),
                    Color(0xFFF8F9FA),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 9,
              top: 5,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2D3133),
                ),
              ),
            ),
            Positioned(
              left: 7,
              bottom: 2,
              child: Container(
                width: 18,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFF54637A),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultSearchHeader extends StatelessWidget {
  const _VaultSearchHeader({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t.notes.vault.title,
          style: const TextStyle(
            color: _VaultColors.onSurface,
            fontSize: 28,
            height: 34 / 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _VaultColors.lowestSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _VaultColors.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SizedBox(
            height: 45,
            child: TextField(
              key: const ValueKey('note_list_search_field'),
              controller: controller,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                color: _VaultColors.onSurface,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: context.t.notes.vault.searchPlaceholder,
                hintStyle: const TextStyle(
                  color: _VaultColors.onSurfaceVariant,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: _VaultColors.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 45,
                ),
                suffixIcon: const Center(child: _VaultCommandKey()),
                suffixIconConstraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 45,
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

class _VaultCommandKey extends StatelessWidget {
  const _VaultCommandKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 30,
      decoration: BoxDecoration(
        color: _VaultColors.lowestSurface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: _VaultColors.outlineVariant),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.keyboard_command_key,
            size: 14,
            color: _VaultColors.onSurfaceVariant,
          ),
          Text(
            'K',
            style: TextStyle(
              color: _VaultColors.onSurfaceVariant,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultCategoryGrid extends StatelessWidget {
  const _VaultCategoryGrid({
    required this.notesCount,
    required this.onOpenNotes,
  });

  final String notesCount;
  final VoidCallback? onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final categories = [
      _VaultCategory(
        title: context.t.notes.vault.categories.memories,
        subtitle: context.t.notes.vault.categories.memoriesCount,
        icon: Icons.memory,
      ),
      _VaultCategory(
        title: context.t.notes.vault.categories.files,
        subtitle: context.t.notes.vault.categories.filesCount,
        icon: Icons.folder_outlined,
      ),
      _VaultCategory(
        key: const ValueKey('note_list_create_button'),
        title: context.t.notes.vault.categories.notes,
        subtitle: notesCount,
        icon: Icons.edit_note,
        onTap: onOpenNotes,
      ),
      _VaultCategory(
        title: context.t.notes.vault.categories.research,
        subtitle: context.t.notes.vault.categories.researchCount,
        icon: Icons.travel_explore,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 720 ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - ((columnCount - 1) * 16)) / columnCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final category in categories)
              SizedBox(
                width: cardWidth,
                height: 132,
                child: _VaultCategoryCard(category: category),
              ),
          ],
        );
      },
    );
  }
}

class _VaultCategory {
  const _VaultCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.key,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Key? key;
  final VoidCallback? onTap;
}

class _VaultCategoryCard extends StatelessWidget {
  const _VaultCategoryCard({required this.category});

  final _VaultCategory category;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: category.key,
      color: _VaultColors.lowestSurface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      shadowColor: const Color(0x1A000000),
      elevation: 1,
      child: InkWell(
        onTap: category.onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VaultIconTile(
                icon: category.icon,
                foreground: _VaultColors.onSurface,
              ),
              const Spacer(),
              Text(
                category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _VaultColors.onSurface,
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                category.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _VaultColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultIconTile extends StatelessWidget {
  const _VaultIconTile({
    required this.icon,
    required this.foreground,
  });

  final IconData icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _VaultColors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 22, color: foreground),
    );
  }
}

class _VaultRecentSection extends StatelessWidget {
  const _VaultRecentSection({
    required this.items,
    required this.showFallback,
    required this.onViewAll,
  });

  final List<_VaultRecentItem> items;
  final bool showFallback;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final displayItems = items.isNotEmpty
        ? items
        : showFallback
            ? [
                _VaultRecentItem(
                  title: context.t.notes.vault.recent.memoryTitle,
                  icon: Icons.memory,
                  color: _VaultColors.onSurface,
                ),
                _VaultRecentItem(
                  title: context.t.notes.vault.recent.researchTitle,
                  icon: Icons.travel_explore,
                  color: _VaultColors.secondary,
                ),
              ]
            : [
                _VaultRecentItem(
                  title: context.t.notes.vault.recent.empty,
                  icon: Icons.edit_note,
                  color: _VaultColors.onSurfaceVariant,
                ),
              ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                context.t.notes.vault.recent.title,
                style: const TextStyle(
                  color: _VaultColors.onSurface,
                  fontSize: 16,
                  height: 24 / 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                context.t.notes.vault.recent.viewAll,
                style: const TextStyle(
                  color: _VaultColors.secondary,
                  fontSize: 11,
                  height: 14 / 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Material(
          color: _VaultColors.lowestSurface,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          shadowColor: const Color(0x1A000000),
          elevation: 1,
          child: Column(
            children: [
              for (var index = 0; index < displayItems.length; index++)
                _VaultRecentRow(
                  item: displayItems[index],
                  highlighted: index == 1,
                  showDivider: index < displayItems.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VaultRecentItem {
  const _VaultRecentItem({
    required this.title,
    required this.icon,
    required this.color,
    this.id,
    this.onTap,
    this.onDelete,
  });

  final String? id;
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Future<void> Function()? onDelete;
}

class _VaultRecentRow extends StatelessWidget {
  const _VaultRecentRow({
    required this.item,
    required this.highlighted,
    required this.showDivider,
  });

  final _VaultRecentItem item;
  final bool highlighted;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final delete = item.onDelete;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: _VaultColors.outlineVariant),
              )
            : null,
      ),
      child: Stack(
        children: [
          if (highlighted)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 3,
                child: ColoredBox(color: _VaultColors.secondary),
              ),
            ),
          InkWell(
            key: item.id == null ? null : ValueKey('note_list_item_${item.id}'),
            onTap: item.onTap,
            onLongPress: delete == null ? null : () => unawaited(delete()),
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _VaultIconTile(icon: item.icon, foreground: item.color),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _VaultColors.onSurface,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (highlighted) ...[
                      const SizedBox(width: 12),
                      Text(
                        context.t.notes.vault.recent.viewDetail,
                        style: const TextStyle(
                          color: _VaultColors.onSurface,
                          fontSize: 11,
                          height: 14 / 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: _VaultColors.onSurface,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _VaultColors {
  static const surface = Color(0xFFF7F9FB);
  static const lowestSurface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const outlineVariant = Color(0xFFC6C6CD);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF45464D);
  static const secondary = Color(0xFF0051D5);
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
