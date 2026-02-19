part of 'chat_page.dart';

extension _ChatPageStateMethodsKTags on _ChatPageState {
  String _tagFilterTooltip(Locale locale) {
    return context.t.chat.tagFilter.tooltip;
  }

  String _clearTagFilterLabel(Locale locale) {
    return context.t.chat.tagFilter.clearFilter;
  }

  Future<void> _openTagFilterSheet() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final selection = await showTagFilterSheetWithModes(
      context: context,
      sessionKey: sessionKey,
      initialIncludeTagIds: _selectedTagFilterIds,
      initialExcludeTagIds: _selectedTagExcludeIds,
      repository: _tagRepository,
    );
    if (!mounted || selection == null) return;

    final nextIncludeIds = selection.includeTags.map((tag) => tag.id).toSet();
    final nextExcludeIds = selection.excludeTags.map((tag) => tag.id).toSet();

    final includeUnchanged =
        nextIncludeIds.length == _selectedTagFilterIds.length &&
            nextIncludeIds.containsAll(_selectedTagFilterIds);
    final excludeUnchanged =
        nextExcludeIds.length == _selectedTagExcludeIds.length &&
            nextExcludeIds.containsAll(_selectedTagExcludeIds);
    if (includeUnchanged && excludeUnchanged) return;

    _setState(() {
      _selectedTagFilterIds
        ..clear()
        ..addAll(nextIncludeIds);
      _selectedTagFilterTagById
        ..clear()
        ..addEntries(selection.includeTags.map((tag) => MapEntry(tag.id, tag)));

      _selectedTagExcludeIds
        ..clear()
        ..addAll(nextExcludeIds);
      _selectedTagExcludeTagById
        ..clear()
        ..addEntries(selection.excludeTags.map((tag) => MapEntry(tag.id, tag)));
    });
    _refresh();
  }

  Future<void> _openMessageTagPicker(Message message) async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final changed = await showMessageTagPicker(
      context: context,
      sessionKey: sessionKey,
      messageId: message.id,
      repository: _tagRepository,
    );
    if (!mounted || !changed) return;

    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refresh();
  }

  Future<List<Message>> _filterMessagesBySelectedTags(
    Uint8List sessionKey,
    List<Message> source,
  ) async {
    if ((_selectedTagFilterIds.isEmpty && _selectedTagExcludeIds.isEmpty) ||
        source.isEmpty) {
      return source;
    }

    var filtered = source;

    if (_selectedTagFilterIds.isNotEmpty) {
      final includeMatchedIds = await _tagRepository.listMessageIdsByTagIds(
        sessionKey,
        widget.conversation.id,
        _selectedTagFilterIds.toList(growable: false),
      );
      if (includeMatchedIds.isEmpty) {
        return const <Message>[];
      }

      final includeMatchedSet = includeMatchedIds.toSet();
      filtered = filtered
          .where((message) => includeMatchedSet.contains(message.id))
          .toList(growable: false);
      if (filtered.isEmpty) {
        return const <Message>[];
      }
    }

    if (_selectedTagExcludeIds.isNotEmpty) {
      final excludeMatchedIds = await _tagRepository.listMessageIdsByTagIds(
        sessionKey,
        widget.conversation.id,
        _selectedTagExcludeIds.toList(growable: false),
      );
      if (excludeMatchedIds.isNotEmpty) {
        final excludeMatchedSet = excludeMatchedIds.toSet();
        filtered = filtered
            .where((message) => !excludeMatchedSet.contains(message.id))
            .toList(growable: false);
      }
    }

    return filtered;
  }

  Widget _buildSelectedTagFilterBar() {
    if (_selectedTagFilterIds.isEmpty && _selectedTagExcludeIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final locale = Localizations.localeOf(context);
    final clearLabel = _clearTagFilterLabel(locale);

    final includeChips = _selectedTagFilterIds.map((tagId) {
      final tag = _selectedTagFilterTagById[tagId];
      final label = tag == null ? tagId : localizeTagName(locale, tag);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          label: Text(label),
          onDeleted: () {
            _setState(() {
              _selectedTagFilterIds.remove(tagId);
              _selectedTagFilterTagById.remove(tagId);
            });
            _refresh();
          },
        ),
      );
    });

    final theme = Theme.of(context);
    final excludeChips = _selectedTagExcludeIds.map((tagId) {
      final tag = _selectedTagExcludeTagById[tagId];
      final baseLabel = tag == null ? tagId : localizeTagName(locale, tag);
      final excludeLabel = '- $baseLabel';
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          label: Text(excludeLabel),
          avatar: Icon(
            Icons.remove,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          backgroundColor: theme.colorScheme.errorContainer,
          onDeleted: () {
            _setState(() {
              _selectedTagExcludeIds.remove(tagId);
              _selectedTagExcludeTagById.remove(tagId);
            });
            _refresh();
          },
        ),
      );
    });

    final chips = <Widget>[
      ...includeChips,
      ...excludeChips,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
          TextButton(
            onPressed: () {
              _setState(() {
                _selectedTagFilterIds.clear();
                _selectedTagFilterTagById.clear();
                _selectedTagExcludeIds.clear();
                _selectedTagExcludeTagById.clear();
              });
              _refresh();
            },
            child: Text(clearLabel),
          ),
        ],
      ),
    );
  }
}
