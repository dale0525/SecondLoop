import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import 'tag_localization.dart';

Future<Tag?> showTagMergeTagSelectorSheet({
  required BuildContext context,
  required String title,
  required List<Tag> tags,
  required String keyPrefix,
  Tag? selectedTag,
}) {
  return showModalBottomSheet<Tag>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return _TagMergeTagSelectorSheet(
        title: title,
        tags: tags,
        keyPrefix: keyPrefix,
        selectedTag: selectedTag,
      );
    },
  );
}

class _TagMergeTagSelectorSheet extends StatefulWidget {
  const _TagMergeTagSelectorSheet({
    required this.title,
    required this.tags,
    required this.keyPrefix,
    this.selectedTag,
  });

  final String title;
  final List<Tag> tags;
  final String keyPrefix;
  final Tag? selectedTag;

  @override
  State<_TagMergeTagSelectorSheet> createState() =>
      _TagMergeTagSelectorSheetState();
}

class _TagSelectorSection {
  const _TagSelectorSection({
    required this.key,
    required this.title,
    required this.tags,
  });

  final String key;
  final String title;
  final List<Tag> tags;
}

class _TagSelectorListEntry {
  const _TagSelectorListEntry.section(this.section) : tag = null;

  const _TagSelectorListEntry.tag(this.tag) : section = null;

  final _TagSelectorSection? section;
  final Tag? tag;

  bool get isSection => section != null;
}

class _TagMergeTagSelectorSheetState extends State<_TagMergeTagSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  Set<String> _searchTerms(Locale locale, Tag tag) {
    final terms = <String>{
      _normalize(localizeTagName(locale, tag)),
      _normalize(tag.name),
    };
    final systemKey = tag.systemKey;
    if (systemKey != null && systemKey.trim().isNotEmpty) {
      terms.add(_normalize(systemKey));
    }
    terms.removeWhere((term) => term.isEmpty);
    return terms;
  }

  int _matchScore(Locale locale, Tag tag, String query) {
    if (query.isEmpty) return 0;

    var bestScore = 0;
    for (final term in _searchTerms(locale, tag)) {
      if (term == query) {
        bestScore = 3;
        break;
      }
      if (term.startsWith(query)) {
        bestScore = bestScore < 2 ? 2 : bestScore;
        continue;
      }
      if (term.contains(query)) {
        bestScore = bestScore < 1 ? 1 : bestScore;
      }
    }
    return bestScore;
  }

  List<Tag> _sortTags(
    Locale locale,
    Iterable<Tag> tags, {
    Map<String, int>? matchScores,
  }) {
    final sorted = List<Tag>.from(tags);
    sorted.sort((left, right) {
      final leftScore = matchScores?[left.id] ?? 0;
      final rightScore = matchScores?[right.id] ?? 0;
      if (leftScore != rightScore) {
        return rightScore.compareTo(leftScore);
      }
      if (left.isSystem != right.isSystem) {
        return left.isSystem ? 1 : -1;
      }

      final leftName = _normalize(localizeTagName(locale, left));
      final rightName = _normalize(localizeTagName(locale, right));
      final nameCompare = leftName.compareTo(rightName);
      if (nameCompare != 0) {
        return nameCompare;
      }
      return left.id.compareTo(right.id);
    });
    return sorted;
  }

  List<_TagSelectorSection> _buildSections(Locale locale) {
    final query = _normalize(_searchController.text);
    final selectedTagId = widget.selectedTag?.id;
    Tag? selectedTag;
    if (selectedTagId != null) {
      for (final tag in widget.tags) {
        if (tag.id == selectedTagId) {
          selectedTag = tag;
          break;
        }
      }
    }

    final sections = <_TagSelectorSection>[];

    if (query.isEmpty) {
      if (selectedTag != null) {
        sections.add(
          _TagSelectorSection(
            key: 'selected',
            title: context.t.chat.tagPicker.manualMergeSelectedSection,
            tags: <Tag>[selectedTag],
          ),
        );
      }

      final remaining = widget.tags.where((tag) => tag.id != selectedTagId);
      final customTags = _sortTags(
        locale,
        remaining.where((tag) => !tag.isSystem),
      );
      final systemTags = _sortTags(
        locale,
        remaining.where((tag) => tag.isSystem),
      );

      if (customTags.isNotEmpty) {
        sections.add(
          _TagSelectorSection(
            key: 'custom',
            title: context.t.chat.tagPicker.manualMergeCustomTagsSection,
            tags: customTags,
          ),
        );
      }
      if (systemTags.isNotEmpty) {
        sections.add(
          _TagSelectorSection(
            key: 'system',
            title: context.t.chat.tagPicker.manualMergeSystemTagsSection,
            tags: systemTags,
          ),
        );
      }
      return sections;
    }

    final matchScores = <String, int>{};
    for (final tag in widget.tags) {
      final score = _matchScore(locale, tag, query);
      if (score > 0) {
        matchScores[tag.id] = score;
      }
    }

    if (selectedTag != null && matchScores.containsKey(selectedTag.id)) {
      sections.add(
        _TagSelectorSection(
          key: 'selected',
          title: context.t.chat.tagPicker.manualMergeSelectedSection,
          tags: <Tag>[selectedTag],
        ),
      );
    }

    final matchedTags = widget.tags.where(
      (tag) => matchScores.containsKey(tag.id) && tag.id != selectedTagId,
    );
    final bestMatches = _sortTags(
      locale,
      matchedTags.where((tag) => (matchScores[tag.id] ?? 0) >= 2),
      matchScores: matchScores,
    );
    final otherMatches = _sortTags(
      locale,
      matchedTags.where((tag) => (matchScores[tag.id] ?? 0) == 1),
      matchScores: matchScores,
    );

    if (bestMatches.isNotEmpty) {
      sections.add(
        _TagSelectorSection(
          key: 'best_matches',
          title: context.t.chat.tagPicker.manualMergeBestMatchesSection,
          tags: bestMatches,
        ),
      );
    }
    if (otherMatches.isNotEmpty) {
      sections.add(
        _TagSelectorSection(
          key: 'other_matches',
          title: context.t.chat.tagPicker.manualMergeOtherMatchesSection,
          tags: otherMatches,
        ),
      );
    }

    return sections;
  }

  List<_TagSelectorListEntry> _buildEntries(Locale locale) {
    final entries = <_TagSelectorListEntry>[];
    for (final section in _buildSections(locale)) {
      entries.add(_TagSelectorListEntry.section(section));
      for (final tag in section.tags) {
        entries.add(_TagSelectorListEntry.tag(tag));
      }
    }
    return entries;
  }

  Widget _buildSectionHeader(_TagSelectorSection section) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        section.title,
        key: ValueKey('${widget.keyPrefix}_section_${section.key}'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  Widget _buildTagOption(Locale locale, ColorScheme colorScheme, Tag tag) {
    final localizedName = localizeTagName(locale, tag);
    final rawLabel =
        tag.isSystem && tag.systemKey != localizedName ? tag.systemKey : null;
    final selected = widget.selectedTag?.id == tag.id;

    return Material(
      color: selected ? colorScheme.secondaryContainer : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colorScheme.secondary : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        key: ValueKey('${widget.keyPrefix}_option_${tag.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(tag),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                selected ? colorScheme.secondary : colorScheme.surfaceVariant,
            foregroundColor: selected
                ? colorScheme.onSecondary
                : colorScheme.onSurfaceVariant,
            child: Icon(
              tag.isSystem ? Icons.auto_awesome : Icons.sell_outlined,
              size: 18,
            ),
          ),
          title: Text(localizedName),
          subtitle: rawLabel == null ? null : Text(rawLabel),
          trailing: selected
              ? Icon(
                  Icons.check_circle,
                  color: colorScheme.secondary,
                )
              : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final entries = _buildEntries(locale);

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(
                widget.title,
                key: ValueKey('${widget.keyPrefix}_title'),
              ),
              trailing: IconButton(
                key: ValueKey('${widget.keyPrefix}_close'),
                tooltip: context.t.common.actions.cancel,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                key: ValueKey('${widget.keyPrefix}_search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.t.chat.tagPicker.manualMergeSearchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        context.t.chat.tagPicker.manualMergeNoMatches,
                        key: ValueKey('${widget.keyPrefix}_empty'),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, index) => entries[index].isSection
                          ? const SizedBox.shrink()
                          : const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry.isSection) {
                          return _buildSectionHeader(entry.section!);
                        }
                        return _buildTagOption(locale, colorScheme, entry.tag!);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
