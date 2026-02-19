import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import 'tag_localization.dart';
import 'tag_repository.dart';

Future<bool> showMessageTagPicker({
  required BuildContext context,
  required Uint8List sessionKey,
  required String messageId,
  TagRepository repository = const TagRepository(),
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return _MessageTagPickerSheet(
        sessionKey: sessionKey,
        messageId: messageId,
        repository: repository,
      );
    },
  );
  return changed ?? false;
}

class _MessageTagPickerSheet extends StatefulWidget {
  const _MessageTagPickerSheet({
    required this.sessionKey,
    required this.messageId,
    required this.repository,
  });

  final Uint8List sessionKey;
  final String messageId;
  final TagRepository repository;

  @override
  State<_MessageTagPickerSheet> createState() => _MessageTagPickerSheetState();
}

class _MessageTagPickerSheetState extends State<_MessageTagPickerSheet> {
  final TextEditingController _inputController = TextEditingController();
  final Set<String> _selectedTagIds = <String>{};

  List<Tag> _allTags = const <Tag>[];
  List<String> _suggestedTags = const <String>[];
  List<TagMergeSuggestion> _mergeSuggestions = const <TagMergeSuggestion>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.repository.listTags(widget.sessionKey),
        widget.repository.listMessageTags(widget.sessionKey, widget.messageId),
        widget.repository
            .listMessageSuggestedTags(widget.sessionKey, widget.messageId),
        widget.repository.listTagMergeSuggestions(widget.sessionKey),
      ]);

      if (!mounted) return;
      final tags = values[0] as List<Tag>;
      final applied = values[1] as List<Tag>;
      final suggested = values[2] as List<String>;
      final mergeSuggestions = values[3] as List<TagMergeSuggestion>;

      setState(() {
        _allTags = tags;
        _selectedTagIds
          ..clear()
          ..addAll(applied.map((tag) => tag.id));
        _suggestedTags = suggested;
        _mergeSuggestions = mergeSuggestions;
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

  String _normalizeName(String value) {
    return value.trim().toLowerCase();
  }

  Tag? _findTagBySuggestion(String suggested) {
    final normalized = _normalizeName(suggested);
    for (final tag in _allTags) {
      final key = tag.systemKey?.trim();
      if (key != null && key.isNotEmpty && _normalizeName(key) == normalized) {
        return tag;
      }
      if (_normalizeName(tag.name) == normalized) {
        return tag;
      }
    }
    return null;
  }

  Future<void> _addOrSelectTagByName(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = _findTagBySuggestion(name);
      final tag = existing ??
          await widget.repository.upsertTag(widget.sessionKey, name);
      if (!mounted) return;

      setState(() {
        final hasTag = _allTags.any((item) => item.id == tag.id);
        if (!hasTag) {
          _allTags = <Tag>[tag, ..._allTags];
        }
        _selectedTagIds.add(tag.id);
        _inputController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final selected = _selectedTagIds.toList(growable: false)..sort();
      await widget.repository
          .setMessageTags(widget.sessionKey, widget.messageId, selected);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _mergeReasonLabel(String reason) {
    return switch (reason) {
      'system_domain' => context.t.chat.tagPicker.mergeReasonSystemDomain,
      'name_compact_match' => context.t.chat.tagPicker.mergeReasonNameCompact,
      'name_contains' => context.t.chat.tagPicker.mergeReasonNameContains,
      _ => context.t.chat.tagPicker.mergeReasonNameContains,
    };
  }

  Future<void> _confirmAndApplyMerge(TagMergeSuggestion suggestion) async {
    if (_saving) return;

    final locale = Localizations.localeOf(context);
    final sourceLabel = localizeTagName(locale, suggestion.sourceTag);
    final targetLabel = localizeTagName(locale, suggestion.targetTag);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.t.chat.tagPicker.mergeDialog.title),
          content: Text(
            context.t.chat.tagPicker.mergeDialog.message(
              source: sourceLabel,
              target: targetLabel,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              key: const ValueKey('tag_picker_merge_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.t.chat.tagPicker.mergeDialog.confirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await widget.repository.mergeTags(
        widget.sessionKey,
        sourceTagId: suggestion.sourceTag.id,
        targetTagId: suggestion.targetTag.id,
      );
      if (!mounted) return;

      await _load();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.tagPicker.mergeApplied(count: updated)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);

    final title = context.t.chat.tagPicker.title;
    final suggestedTitle = context.t.chat.tagPicker.suggested;
    final mergeSuggestionsTitle = context.t.chat.tagPicker.mergeSuggestions;
    final mergeActionLabel = context.t.chat.tagPicker.mergeAction;
    final allTitle = context.t.chat.tagPicker.all;
    final addHint = context.t.chat.tagPicker.inputHint;
    final addLabel = context.t.chat.tagPicker.add;
    final saveLabel = context.t.chat.tagPicker.save;
    final closeLabel = context.t.common.actions.cancel;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(title),
              trailing: IconButton(
                tooltip: closeLabel,
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_suggestedTags.isNotEmpty) ...[
                        Text(
                          suggestedTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _suggestedTags.map((suggested) {
                            final existing = _findTagBySuggestion(suggested);
                            final selected = existing != null &&
                                _selectedTagIds.contains(existing.id);
                            final label = existing != null
                                ? localizeTagName(locale, existing)
                                : suggested;
                            return ActionChip(
                              label: Text(label),
                              avatar: const Icon(Icons.auto_awesome, size: 16),
                              onPressed: _saving
                                  ? null
                                  : () => unawaited(
                                      _addOrSelectTagByName(suggested)),
                              backgroundColor: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withOpacity(0.6)
                                  : null,
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_mergeSuggestions.isNotEmpty) ...[
                        Text(
                          mergeSuggestionsTitle,
                          key: const ValueKey('tag_picker_merge_title'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Column(
                          key: const ValueKey('tag_picker_merge_suggestions'),
                          children: _mergeSuggestions.map((suggestion) {
                            final sourceLabel =
                                localizeTagName(locale, suggestion.sourceTag);
                            final targetLabel =
                                localizeTagName(locale, suggestion.targetTag);
                            final sourceUsage =
                                suggestion.sourceUsageCount.toInt();
                            final mergeTitle = '$sourceLabel -> $targetLabel';
                            final mergeSubtitle =
                                '${_mergeReasonLabel(suggestion.reason)} · ${context.t.chat.tagPicker.mergeSuggestionMessages(count: sourceUsage)}';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(mergeTitle),
                                subtitle: Text(mergeSubtitle),
                                trailing: TextButton(
                                  key: ValueKey(
                                    'tag_picker_merge_apply_${suggestion.sourceTag.id}_${suggestion.targetTag.id}',
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => unawaited(
                                            _confirmAndApplyMerge(suggestion),
                                          ),
                                  child: Text(mergeActionLabel),
                                ),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        allTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allTags.map((tag) {
                          final selected = _selectedTagIds.contains(tag.id);
                          return FilterChip(
                            label: Text(localizeTagName(locale, tag)),
                            selected: selected,
                            onSelected: _saving
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value) {
                                        _selectedTagIds.add(tag.id);
                                      } else {
                                        _selectedTagIds.remove(tag.id);
                                      }
                                    });
                                  },
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: _saving
                                  ? null
                                  : (value) =>
                                      unawaited(_addOrSelectTagByName(value)),
                              decoration: InputDecoration(
                                hintText: addHint,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _saving
                                ? null
                                : () => unawaited(
                                      _addOrSelectTagByName(
                                        _inputController.text,
                                      ),
                                    ),
                            child: Text(addLabel),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(closeLabel),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: Text(saveLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
