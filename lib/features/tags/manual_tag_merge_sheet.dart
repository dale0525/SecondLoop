import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import 'tag_localization.dart';
import 'tag_merge_tag_selector_sheet.dart';
import 'tag_repository.dart';

class ManualTagMergeSheetResult {
  const ManualTagMergeSheetResult({
    this.sourceTag,
    this.targetTag,
    this.feedbackReason,
    this.didChangeSuggestions = false,
  });

  final Tag? sourceTag;
  final Tag? targetTag;
  final String? feedbackReason;
  final bool didChangeSuggestions;
}

Future<ManualTagMergeSheetResult?> showManualTagMergeSheet({
  required BuildContext context,
  required Uint8List sessionKey,
  required List<Tag> allTags,
  TagRepository repository = const TagRepository(),
}) {
  return showModalBottomSheet<ManualTagMergeSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) {
      return _ManualTagMergeSheet(
        sessionKey: sessionKey,
        allTags: allTags,
        repository: repository,
      );
    },
  );
}

class _ManualTagMergeSheet extends StatefulWidget {
  const _ManualTagMergeSheet({
    required this.sessionKey,
    required this.allTags,
    required this.repository,
  });

  final Uint8List sessionKey;
  final List<Tag> allTags;
  final TagRepository repository;

  @override
  State<_ManualTagMergeSheet> createState() => _ManualTagMergeSheetState();
}

class _ManualTagMergeSheetState extends State<_ManualTagMergeSheet> {
  static const int _hiddenSearchThreshold = 6;
  final TextEditingController _hiddenSearchController = TextEditingController();

  Tag? _selectedSourceTag;
  Tag? _selectedTargetTag;
  List<TagMergeSuggestion> _hiddenSuggestions = const <TagMergeSuggestion>[];
  bool _loadingHiddenSuggestions = true;
  bool _hiddenExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHiddenSuggestions());
  }

  @override
  void dispose() {
    _hiddenSearchController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  List<Tag> get _sourceCandidates {
    return widget.allTags.where((tag) => !tag.isSystem).toList(growable: false);
  }

  List<Tag> get _targetCandidates {
    final sourceTag = _selectedSourceTag;
    if (sourceTag == null) {
      return const <Tag>[];
    }
    return widget.allTags
        .where((tag) => tag.id != sourceTag.id)
        .toList(growable: false);
  }

  List<TagMergeSuggestion> get _filteredHiddenSuggestions {
    final query = _normalize(_hiddenSearchController.text);
    if (query.isEmpty) {
      return _hiddenSuggestions;
    }

    final locale = Localizations.localeOf(context);
    return _hiddenSuggestions.where((suggestion) {
      final source = localizeTagName(locale, suggestion.sourceTag);
      final target = localizeTagName(locale, suggestion.targetTag);
      return _normalize(source).contains(query) ||
          _normalize(target).contains(query);
    }).toList(growable: false);
  }

  String _mergeReasonLabel(String reason) {
    return switch (reason) {
      'system_domain' => context.t.chat.tagPicker.mergeReasonSystemDomain,
      'name_compact_match' => context.t.chat.tagPicker.mergeReasonNameCompact,
      'name_contains' => context.t.chat.tagPicker.mergeReasonNameContains,
      _ => context.t.chat.tagPicker.mergeReasonNameContains,
    };
  }

  Future<void> _loadHiddenSuggestions() async {
    try {
      final hiddenSuggestions =
          await widget.repository.listHiddenTagMergeSuggestions(
        widget.sessionKey,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _hiddenSuggestions = hiddenSuggestions;
        _loadingHiddenSuggestions = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHiddenSuggestions = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickSourceTag() async {
    final sourceTag = await showTagMergeTagSelectorSheet(
      context: context,
      title: context.t.chat.tagPicker.manualMergeSourceTitle,
      tags: _sourceCandidates,
      keyPrefix: 'manual_tag_merge_source_selector',
      selectedTag: _selectedSourceTag,
    );
    if (sourceTag == null || !mounted) return;

    setState(() {
      _selectedSourceTag = sourceTag;
      if (_selectedTargetTag?.id == sourceTag.id) {
        _selectedTargetTag = null;
      }
    });
  }

  Future<void> _pickTargetTag() async {
    final sourceTag = _selectedSourceTag;
    if (sourceTag == null) return;

    final targetTag = await showTagMergeTagSelectorSheet(
      context: context,
      title: context.t.chat.tagPicker.manualMergeTargetTitle,
      tags: _targetCandidates,
      keyPrefix: 'manual_tag_merge_target_selector',
      selectedTag: _selectedTargetTag,
    );
    if (targetTag == null || !mounted) return;

    setState(() {
      _selectedTargetTag = targetTag;
    });
  }

  void _acceptHiddenSuggestion(TagMergeSuggestion suggestion) {
    Navigator.of(context).pop(
      ManualTagMergeSheetResult(
        sourceTag: suggestion.sourceTag,
        targetTag: suggestion.targetTag,
        feedbackReason: suggestion.reason,
      ),
    );
  }

  void _closeSheet() {
    Navigator.of(context).pop(const ManualTagMergeSheetResult());
  }

  void _submit() {
    final sourceTag = _selectedSourceTag;
    final targetTag = _selectedTargetTag;
    if (sourceTag == null ||
        targetTag == null ||
        sourceTag.id == targetTag.id) {
      return;
    }

    Navigator.of(context).pop(
      ManualTagMergeSheetResult(
        sourceTag: sourceTag,
        targetTag: targetTag,
      ),
    );
  }

  Widget _buildSelectorCard({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required String? selectedLabel,
    required VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled
          ? colorScheme.surface
          : colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.surfaceVariant,
                foregroundColor: colorScheme.onSurfaceVariant,
                child: Icon(icon, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedLabel ?? subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: selectedLabel == null
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              )
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                isEnabled ? Icons.chevron_right : Icons.lock_outline,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenSuggestionTile(
    Locale locale,
    TagMergeSuggestion suggestion,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceLabel = localizeTagName(locale, suggestion.sourceTag);
    final targetLabel = localizeTagName(locale, suggestion.targetTag);
    final sourceUsage = suggestion.sourceUsageCount.toInt();
    final mergeTitle = '$sourceLabel → $targetLabel';
    final mergeSubtitle =
        '${_mergeReasonLabel(suggestion.reason)} · ${context.t.chat.tagPicker.mergeSuggestionMessages(count: sourceUsage)}';

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        key: ValueKey(
          'manual_tag_merge_accept_${suggestion.sourceTag.id}_${suggestion.targetTag.id}',
        ),
        onTap: () => _acceptHiddenSuggestion(suggestion),
        title: Text(mergeTitle),
        subtitle: Text(mergeSubtitle),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            context.t.chat.tagPicker.hiddenMergeAcceptAction,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final filteredHiddenSuggestions = _filteredHiddenSuggestions;
    final canSubmit = _selectedSourceTag != null && _selectedTargetTag != null;
    final showHiddenSearch =
        _hiddenSuggestions.length >= _hiddenSearchThreshold && _hiddenExpanded;
    final hiddenTitle =
        '${context.t.chat.tagPicker.hiddenMergeSuggestions} (${_hiddenSuggestions.length})';
    final hiddenListHeight = math.min(
      320.0,
      math.max(120.0, filteredHiddenSuggestions.length * 88.0),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(
                context.t.chat.tagPicker.manualMergeAction,
                key: const ValueKey('manual_tag_merge_title'),
              ),
              trailing: IconButton(
                key: const ValueKey('manual_tag_merge_close'),
                tooltip: context.t.common.actions.cancel,
                icon: const Icon(Icons.close),
                onPressed: _closeSheet,
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _buildSelectorCard(
                    key: const ValueKey('manual_tag_merge_pick_source'),
                    icon: Icons.call_split,
                    title: context.t.chat.tagPicker.manualMergeSourceTitle,
                    subtitle: context.t.chat.tagPicker.manualMergeSourceHint,
                    selectedLabel: _selectedSourceTag == null
                        ? null
                        : localizeTagName(locale, _selectedSourceTag!),
                    onTap: _pickSourceTag,
                  ),
                  const SizedBox(height: 12),
                  _buildSelectorCard(
                    key: const ValueKey('manual_tag_merge_pick_target'),
                    icon: Icons.merge_type,
                    title: context.t.chat.tagPicker.manualMergeTargetTitle,
                    subtitle: _selectedSourceTag == null
                        ? context.t.chat.tagPicker.manualMergeSelectSourceFirst
                        : context.t.chat.tagPicker.manualMergeTargetHint,
                    selectedLabel: _selectedTargetTag == null
                        ? null
                        : localizeTagName(locale, _selectedTargetTag!),
                    onTap: _selectedSourceTag == null ? null : _pickTargetTag,
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    key: const ValueKey('manual_tag_merge_hidden_expand'),
                    borderRadius: BorderRadius.circular(12),
                    onTap:
                        _loadingHiddenSuggestions || _hiddenSuggestions.isEmpty
                            ? null
                            : () => setState(() {
                                  _hiddenExpanded = !_hiddenExpanded;
                                }),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            hiddenTitle,
                            key:
                                const ValueKey('manual_tag_merge_hidden_title'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Icon(
                          _hiddenExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                      ],
                    ),
                  ),
                  if (_hiddenExpanded) ...[
                    const SizedBox(height: 8),
                    if (_loadingHiddenSuggestions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      if (showHiddenSearch) ...[
                        TextField(
                          key: const ValueKey('manual_tag_merge_hidden_search'),
                          controller: _hiddenSearchController,
                          onChanged: (_) => setState(() {}),
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText:
                                context.t.chat.tagPicker.manualMergeSearchHint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (filteredHiddenSuggestions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              context.t.chat.tagPicker.manualMergeNoMatches,
                            ),
                          ),
                        )
                      else if (filteredHiddenSuggestions.length <= 3)
                        Column(
                          children: [
                            for (var index = 0;
                                index < filteredHiddenSuggestions.length;
                                index++) ...[
                              if (index > 0) const SizedBox(height: 8),
                              _buildHiddenSuggestionTile(
                                locale,
                                filteredHiddenSuggestions[index],
                              ),
                            ],
                          ],
                        )
                      else
                        SizedBox(
                          height: hiddenListHeight,
                          child: ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: filteredHiddenSuggestions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              return _buildHiddenSuggestionTile(
                                locale,
                                filteredHiddenSuggestions[index],
                              );
                            },
                          ),
                        ),
                    ],
                  ],
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _closeSheet,
                    child: Text(context.t.common.actions.cancel),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('manual_tag_merge_submit'),
                    onPressed: canSubmit ? _submit : null,
                    child: Text(context.t.common.actions.continueLabel),
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
