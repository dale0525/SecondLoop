part of 'chat_page.dart';

const _kTopicThreadAutoTitleMaxRunes = 24;

extension _ChatPageStateMethodsNTopicThreads on _ChatPageState {
  String _topicThreadActionLabel(Locale locale) {
    return context.t.chat.topicThread.actionLabel;
  }

  String _topicThreadFilterBarClearLabel(Locale locale) {
    return context.t.chat.topicThread.clear;
  }

  String _topicThreadUntitledLabel(Locale locale) {
    return context.t.chat.topicThread.untitled;
  }

  String _topicThreadDisplayLabel(Locale locale, TopicThread thread) {
    final raw = thread.title?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    final shortId =
        thread.id.length >= 6 ? thread.id.substring(0, 6) : thread.id;
    return '${_topicThreadUntitledLabel(locale)} #$shortId';
  }

  String? _topicThreadAutoTitleFromMessage(Message message) {
    final normalized =
        _displayTextForMessage(message).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return null;
    }

    final runeCount = normalized.runes.length;
    if (runeCount <= _kTopicThreadAutoTitleMaxRunes) {
      return normalized;
    }

    final clipped = String.fromCharCodes(
      normalized.runes.take(_kTopicThreadAutoTitleMaxRunes),
    );
    return '${clipped.trimRight()}...';
  }

  Future<TopicThread?> _resolveTopicThreadForMessage(
    Uint8List sessionKey,
    Message message,
  ) async {
    final threads = await _topicThreadRepository.listTopicThreads(
      sessionKey,
      widget.conversation.id,
    );

    for (final thread in threads) {
      final ids = await _topicThreadRepository.listTopicThreadMessageIds(
        sessionKey,
        thread.id,
      );
      if (ids.contains(message.id)) {
        return thread;
      }
    }

    final created = await _topicThreadRepository.createTopicThread(
      sessionKey,
      widget.conversation.id,
      title: _topicThreadAutoTitleFromMessage(message),
    );
    final currentIds = await _topicThreadRepository.listTopicThreadMessageIds(
      sessionKey,
      created.id,
    );
    if (!currentIds.contains(message.id)) {
      await _topicThreadRepository.setTopicThreadMessageIds(
        sessionKey,
        created.id,
        <String>[...currentIds, message.id],
      );
    }
    if (mounted) {
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    }
    return created;
  }

  void _setActiveTopicThread(TopicThread thread) {
    _setState(() {
      _activeTopicThreadId = thread.id;
      _activeTopicThread = thread;
    });
    _refresh();
  }

  void _clearActiveTopicThread() {
    _setState(() {
      _activeTopicThreadId = null;
      _activeTopicThread = null;
    });
    _refresh();
  }

  Future<List<Message>> _filterMessagesByActiveTopicThread(
    Uint8List sessionKey,
    List<Message> source,
  ) async {
    final threadId = _activeTopicThreadId;
    if (threadId == null || source.isEmpty) {
      return source;
    }

    final messageIds = await _topicThreadRepository.listTopicThreadMessageIds(
      sessionKey,
      threadId,
    );
    if (messageIds.isEmpty) {
      return const <Message>[];
    }

    final allowed = messageIds.toSet();
    return source
        .where((message) => allowed.contains(message.id))
        .toList(growable: false);
  }

  Widget _buildActiveTopicThreadBar() {
    final thread = _activeTopicThread;
    if (thread == null) {
      return const SizedBox.shrink();
    }

    final locale = Localizations.localeOf(context);
    final clearLabel = _topicThreadFilterBarClearLabel(locale);
    final label = _topicThreadDisplayLabel(locale, thread);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: InputChip(
              key: const ValueKey('topic_thread_active_chip'),
              label: Text(label),
              onDeleted: _clearActiveTopicThread,
            ),
          ),
          TextButton(
            onPressed: _clearActiveTopicThread,
            child: Text(clearLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openMessageTopicThreadPicker(Message message) async {
    if (kIsWeb) return;

    final sessionKey = SessionScope.of(context).sessionKey;
    final thread = await _resolveTopicThreadForMessage(sessionKey, message);
    if (!mounted || thread == null) {
      return;
    }

    _setActiveTopicThread(thread);
  }
}
