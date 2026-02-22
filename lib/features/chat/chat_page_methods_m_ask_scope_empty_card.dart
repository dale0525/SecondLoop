part of 'chat_page.dart';

extension _ChatPageStateMethodsMAskScopeEmptyCard on _ChatPageState {
  Future<bool> _hasActiveEmbeddingProfile(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final profiles = await backend.listEmbeddingProfiles(sessionKey);
      for (final profile in profiles) {
        if (profile.isActive) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _clearAskScopeEmptyState() {
    _askScopeEmptyQuestion = null;
    _askScopeEmptyAnswer = null;
  }

  void _captureAskScopeEmptyState({
    required String question,
    required String answer,
  }) {
    if (AskScopeEmptyResponse.matches(answer)) {
      _askScopeEmptyQuestion = question;
      _askScopeEmptyAnswer = answer;
      return;
    }

    _askScopeEmptyQuestion = null;
    _askScopeEmptyAnswer = null;
  }

  String _askScopeEmptyTitle() {
    return context.t.chat.askScopeEmpty.title;
  }

  String _askScopeEmptyActionLabel(AskScopeEmptyAction action) {
    return switch (action) {
      AskScopeEmptyAction.expandTimeWindow =>
        context.t.chat.askScopeEmpty.actions.expandTimeWindow,
      AskScopeEmptyAction.removeIncludeTags =>
        context.t.chat.askScopeEmpty.actions.removeIncludeTags,
      AskScopeEmptyAction.switchScopeToAll =>
        context.t.chat.askScopeEmpty.actions.switchScopeToAll,
    };
  }

  IconData _askScopeEmptyActionIcon(AskScopeEmptyAction action) {
    return switch (action) {
      AskScopeEmptyAction.expandTimeWindow => Icons.date_range_outlined,
      AskScopeEmptyAction.removeIncludeTags => Icons.sell_outlined,
      AskScopeEmptyAction.switchScopeToAll => Icons.filter_alt_outlined,
    };
  }

  ValueKey<String> _askScopeEmptyActionKey(AskScopeEmptyAction action) {
    return ValueKey<String>('ask_scope_empty_action_${action.name}');
  }

  Future<void> _runAskScopeEmptyAction(AskScopeEmptyAction action) async {
    if (_asking || _sending || _recordingAudio) return;

    final question = _askScopeEmptyQuestion?.trim();
    if (question == null || question.isEmpty) return;

    switch (action) {
      case AskScopeEmptyAction.expandTimeWindow:
        break;
      case AskScopeEmptyAction.removeIncludeTags:
        if (_selectedTagFilterIds.isNotEmpty) {
          _setState(() {
            _selectedTagFilterIds.clear();
            _selectedTagFilterTagById.clear();
          });
          _refresh();
        }
        break;
      case AskScopeEmptyAction.switchScopeToAll:
        if (_thisThreadOnly) {
          _setState(() {
            _thisThreadOnly = false;
          });
          _refresh();
        }
        break;
    }

    await _askAi(
      questionOverride: question,
      forceDisableTimeWindow: action == AskScopeEmptyAction.expandTimeWindow,
    );
  }

  Widget _buildAskScopeEmptyCard() {
    final question = _askScopeEmptyQuestion?.trim();
    final answer = _askScopeEmptyAnswer?.trim();
    if (question == null || question.isEmpty) return const SizedBox.shrink();
    if (answer == null || answer.isEmpty) return const SizedBox.shrink();

    final title = _askScopeEmptyTitle();
    final subtitle = AskScopeEmptyResponse.summaryLine(answer);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SlSurface(
            key: const ValueKey('ask_scope_empty_card'),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('ask_scope_empty_close'),
                      tooltip: context.t.common.actions.cancel,
                      onPressed: () {
                        _setState(_clearAskScopeEmptyState);
                      },
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Text(subtitle),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in AskScopeEmptyAction.values)
                      SlButton(
                        key: _askScopeEmptyActionKey(action),
                        variant: SlButtonVariant.outline,
                        onPressed: () =>
                            unawaited(_runAskScopeEmptyAction(action)),
                        icon: Icon(_askScopeEmptyActionIcon(action), size: 18),
                        child: Text(_askScopeEmptyActionLabel(action)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
