import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import 'tag_localization.dart';
import 'tag_repository.dart';

class TagFilterSelection {
  const TagFilterSelection({
    required this.includeTags,
    required this.excludeTags,
  });

  final List<Tag> includeTags;
  final List<Tag> excludeTags;
}

Future<List<Tag>?> showTagFilterSheet({
  required BuildContext context,
  required Uint8List sessionKey,
  required Set<String> initialSelectedTagIds,
  TagRepository repository = const TagRepository(),
}) async {
  final selection = await showTagFilterSheetWithModes(
    context: context,
    sessionKey: sessionKey,
    initialIncludeTagIds: initialSelectedTagIds,
    initialExcludeTagIds: const <String>{},
    repository: repository,
  );
  return selection?.includeTags;
}

Future<TagFilterSelection?> showTagFilterSheetWithModes({
  required BuildContext context,
  required Uint8List sessionKey,
  required Set<String> initialIncludeTagIds,
  required Set<String> initialExcludeTagIds,
  TagRepository repository = const TagRepository(),
}) {
  return showModalBottomSheet<TagFilterSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return _TagFilterSheet(
        sessionKey: sessionKey,
        initialIncludeTagIds: initialIncludeTagIds,
        initialExcludeTagIds: initialExcludeTagIds,
        repository: repository,
      );
    },
  );
}

enum _TagFilterMode {
  none,
  include,
  exclude,
}

class _TagFilterSheet extends StatefulWidget {
  const _TagFilterSheet({
    required this.sessionKey,
    required this.initialIncludeTagIds,
    required this.initialExcludeTagIds,
    required this.repository,
  });

  final Uint8List sessionKey;
  final Set<String> initialIncludeTagIds;
  final Set<String> initialExcludeTagIds;
  final TagRepository repository;

  @override
  State<_TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<_TagFilterSheet> {
  final Map<String, _TagFilterMode> _modeByTagId = <String, _TagFilterMode>{};
  List<Tag> _allTags = const <Tag>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final tagId in widget.initialIncludeTagIds) {
      _modeByTagId[tagId] = _TagFilterMode.include;
    }
    for (final tagId in widget.initialExcludeTagIds) {
      if (_modeByTagId[tagId] != _TagFilterMode.include) {
        _modeByTagId[tagId] = _TagFilterMode.exclude;
      }
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final tags = await widget.repository.listTags(widget.sessionKey);
      if (!mounted) return;
      setState(() {
        _allTags = tags;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  _TagFilterMode _modeOf(String tagId) =>
      _modeByTagId[tagId] ?? _TagFilterMode.none;

  void _cycleTagMode(String tagId) {
    final next = switch (_modeOf(tagId)) {
      _TagFilterMode.none => _TagFilterMode.include,
      _TagFilterMode.include => _TagFilterMode.exclude,
      _TagFilterMode.exclude => _TagFilterMode.none,
    };

    setState(() {
      if (next == _TagFilterMode.none) {
        _modeByTagId.remove(tagId);
      } else {
        _modeByTagId[tagId] = next;
      }
    });
  }

  Color? _selectedColorFor(
    ThemeData theme,
    _TagFilterMode mode,
  ) {
    return switch (mode) {
      _TagFilterMode.include => theme.colorScheme.secondaryContainer,
      _TagFilterMode.exclude => theme.colorScheme.errorContainer,
      _TagFilterMode.none => null,
    };
  }

  Icon? _avatarFor(
    ThemeData theme,
    _TagFilterMode mode,
  ) {
    final color = switch (mode) {
      _TagFilterMode.include => theme.colorScheme.onSecondaryContainer,
      _TagFilterMode.exclude => theme.colorScheme.onErrorContainer,
      _TagFilterMode.none => theme.colorScheme.onSurfaceVariant,
    };

    return switch (mode) {
      _TagFilterMode.include => Icon(Icons.add, size: 16, color: color),
      _TagFilterMode.exclude => Icon(Icons.remove, size: 16, color: color),
      _TagFilterMode.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);

    final title = context.t.chat.tagFilter.sheet.title;
    final applyLabel = context.t.chat.tagFilter.sheet.apply;
    final clearLabel = context.t.chat.tagFilter.sheet.clear;
    final closeLabel = context.t.common.actions.cancel;
    final emptyLabel = context.t.chat.tagFilter.sheet.empty;
    final includeHint = context.t.chat.tagFilter.sheet.includeHint;
    final excludeHint = context.t.chat.tagFilter.sheet.excludeHint;
    final modeHintLabel = '$includeHint  ·  $excludeHint';

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Column(
        children: [
          ListTile(
            title: Text(title),
            subtitle: Text(modeHintLabel),
            trailing: IconButton(
              tooltip: closeLabel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _error != null
                    ? Center(child: Text(_error!))
                    : _allTags.isEmpty
                        ? Center(child: Text(emptyLabel))
                        : SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _allTags.map((tag) {
                                final theme = Theme.of(context);
                                final mode = _modeOf(tag.id);
                                final selected = mode != _TagFilterMode.none;

                                return FilterChip(
                                  key: ValueKey('tag_filter_chip_${tag.id}'),
                                  label: Text(localizeTagName(locale, tag)),
                                  selected: selected,
                                  showCheckmark: false,
                                  selectedColor: _selectedColorFor(theme, mode),
                                  avatar: _avatarFor(theme, mode),
                                  onSelected: (_) => _cycleTagMode(tag.id),
                                );
                              }).toList(growable: false),
                            ),
                          ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _modeByTagId.clear();
                    });
                  },
                  child: Text(clearLabel),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(closeLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final includeTags = _allTags
                        .where(
                            (tag) => _modeOf(tag.id) == _TagFilterMode.include)
                        .toList(growable: false);
                    final excludeTags = _allTags
                        .where(
                            (tag) => _modeOf(tag.id) == _TagFilterMode.exclude)
                        .toList(growable: false);
                    Navigator.of(context).pop(
                      TagFilterSelection(
                        includeTags: includeTags,
                        excludeTags: excludeTags,
                      ),
                    );
                  },
                  child: Text(applyLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
