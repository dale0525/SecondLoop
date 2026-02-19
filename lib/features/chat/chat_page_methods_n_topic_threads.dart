part of 'chat_page.dart';

const _kTopicThreadFilterActionCreate = '__topic_thread_create__';
const _kTopicThreadFilterActionClear = '__topic_thread_clear__';
const _kTopicThreadManageActionRenamePrefix = '__topic_thread_manage_rename__:';
const _kTopicThreadManageActionDeletePrefix = '__topic_thread_manage_delete__:';

extension _ChatPageStateMethodsNTopicThreads on _ChatPageState {
  String _topicThreadFilterTooltip(Locale locale) {
    return context.t.chat.topicThread.filterTooltip;
  }

  String _topicThreadActionLabel(Locale locale) {
    return context.t.chat.topicThread.actionLabel;
  }

  String _topicThreadCreateLabel(Locale locale) {
    return context.t.chat.topicThread.create;
  }

  String _topicThreadClearFilterLabel(Locale locale) {
    return context.t.chat.topicThread.clearFilter;
  }

  String _topicThreadFilterBarClearLabel(Locale locale) {
    return context.t.chat.topicThread.clear;
  }

  String _topicThreadManageLabel(Locale locale) {
    return context.t.chat.topicThread.manage;
  }

  String _topicThreadRenameLabel(Locale locale) {
    return context.t.chat.topicThread.rename;
  }

  String _topicThreadDeleteLabel(Locale locale) {
    return context.t.chat.topicThread.delete;
  }

  String _topicThreadDeleteDialogTitle(Locale locale) {
    return context.t.chat.topicThread.deleteDialog.title;
  }

  String _topicThreadDeleteDialogBody(Locale locale) {
    return context.t.chat.topicThread.deleteDialog.message;
  }

  String _topicThreadDeleteConfirmLabel(Locale locale) {
    return context.t.chat.topicThread.deleteDialog.confirm;
  }

  String _topicThreadAddMessageLabel(Locale locale) {
    return context.t.chat.topicThread.addMessage;
  }

  String _topicThreadRemoveMessageLabel(Locale locale) {
    return context.t.chat.topicThread.removeMessage;
  }

  String _topicThreadCreateDialogTitle(Locale locale) {
    return context.t.chat.topicThread.createDialogTitle;
  }

  String _topicThreadRenameDialogTitle(Locale locale) {
    return context.t.chat.topicThread.renameDialogTitle;
  }

  String _topicThreadTitleFieldLabel(Locale locale) {
    return context.t.chat.topicThread.titleFieldLabel;
  }

  String _topicThreadUntitledLabel(Locale locale) {
    return context.t.chat.topicThread.untitled;
  }

  bool _isTopicThreadManageRenameAction(String value) {
    return value.startsWith(_kTopicThreadManageActionRenamePrefix);
  }

  bool _isTopicThreadManageDeleteAction(String value) {
    return value.startsWith(_kTopicThreadManageActionDeletePrefix);
  }

  String? _topicThreadIdFromManageAction(String value, String prefix) {
    if (!value.startsWith(prefix)) return null;
    final threadId = value.substring(prefix.length).trim();
    return threadId.isEmpty ? null : threadId;
  }

  TopicThread? _findTopicThreadById(
      List<TopicThread> threads, String threadId) {
    for (final thread in threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
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

  Future<void> _openTopicThreadFilterSheet() async {
    if (kIsWeb) return;

    final locale = Localizations.localeOf(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final threads = await _topicThreadRepository.listTopicThreads(
      sessionKey,
      widget.conversation.id,
    );
    if (!mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final createLabel = _topicThreadCreateLabel(locale);
        final clearLabel = _topicThreadClearFilterLabel(locale);
        final manageLabel = _topicThreadManageLabel(locale);
        final renameLabel = _topicThreadRenameLabel(locale);
        final deleteLabel = _topicThreadDeleteLabel(locale);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (_activeTopicThreadId != null)
                ListTile(
                  key: const ValueKey('topic_thread_filter_clear'),
                  leading: const Icon(Icons.clear_all_rounded),
                  title: Text(clearLabel),
                  onTap: () =>
                      Navigator.of(context).pop(_kTopicThreadFilterActionClear),
                ),
              for (final thread in threads)
                ListTile(
                  key: ValueKey('topic_thread_filter_${thread.id}'),
                  leading: Icon(
                    _activeTopicThreadId == thread.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(_topicThreadDisplayLabel(locale, thread)),
                  trailing: PopupMenuButton<String>(
                    key: ValueKey('topic_thread_filter_manage_${thread.id}'),
                    tooltip: manageLabel,
                    onSelected: (value) => Navigator.of(context).pop(value),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: ValueKey(
                          'topic_thread_filter_manage_rename_${thread.id}',
                        ),
                        value:
                            '$_kTopicThreadManageActionRenamePrefix${thread.id}',
                        child: Text(renameLabel),
                      ),
                      PopupMenuItem(
                        key: ValueKey(
                          'topic_thread_filter_manage_delete_${thread.id}',
                        ),
                        value:
                            '$_kTopicThreadManageActionDeletePrefix${thread.id}',
                        child: Text(deleteLabel),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                  onTap: () => Navigator.of(context).pop(thread.id),
                ),
              ListTile(
                key: const ValueKey('topic_thread_filter_create'),
                leading: const Icon(Icons.add_rounded),
                title: Text(createLabel),
                onTap: () =>
                    Navigator.of(context).pop(_kTopicThreadFilterActionCreate),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) return;

    if (selected == _kTopicThreadFilterActionCreate) {
      final created = await _promptCreateTopicThread(sessionKey);
      if (!mounted || created == null) return;
      _setState(() {
        _activeTopicThreadId = created.id;
        _activeTopicThread = created;
      });
      _refresh();
      return;
    }

    if (selected == _kTopicThreadFilterActionClear) {
      _setState(() {
        _activeTopicThreadId = null;
        _activeTopicThread = null;
      });
      _refresh();
      return;
    }

    if (_isTopicThreadManageRenameAction(selected)) {
      final threadId = _topicThreadIdFromManageAction(
        selected,
        _kTopicThreadManageActionRenamePrefix,
      );
      if (threadId == null) return;

      final target = _findTopicThreadById(threads, threadId);
      if (target == null) return;

      final updated = await _promptRenameTopicThread(sessionKey, target);
      if (!mounted || updated == null) return;

      if (_activeTopicThreadId == updated.id) {
        _setState(() {
          _activeTopicThread = updated;
        });
      }
      _refresh();
      return;
    }

    if (_isTopicThreadManageDeleteAction(selected)) {
      final threadId = _topicThreadIdFromManageAction(
        selected,
        _kTopicThreadManageActionDeletePrefix,
      );
      if (threadId == null) return;

      final target = _findTopicThreadById(threads, threadId);
      if (target == null) return;

      final deleted = await _confirmDeleteTopicThread(sessionKey, target);
      if (!mounted || !deleted) return;

      if (_activeTopicThreadId == target.id) {
        _setState(() {
          _activeTopicThreadId = null;
          _activeTopicThread = null;
        });
      }
      _refresh();
      return;
    }

    final target = _findTopicThreadById(threads, selected) ??
        TopicThread(
          id: selected,
          conversationId: widget.conversation.id,
          title: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        );
    _setState(() {
      _activeTopicThreadId = target.id;
      _activeTopicThread = target;
    });
    _refresh();
  }

  Future<String?> _promptTopicThreadTitle({
    required String dialogTitle,
    String? initialTitle,
  }) async {
    final locale = Localizations.localeOf(context);
    var draftTitle = initialTitle?.trim() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final fieldLabel = _topicThreadTitleFieldLabel(locale);
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextFormField(
            initialValue: draftTitle,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: fieldLabel),
            onChanged: (value) {
              draftTitle = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(this.context.t.common.actions.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(this.context.t.common.actions.save),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) return null;

    return draftTitle.trim();
  }

  Future<TopicThread?> _promptCreateTopicThread(
    Uint8List sessionKey, {
    String? initialTitle,
  }) async {
    final locale = Localizations.localeOf(context);
    final rawTitle = await _promptTopicThreadTitle(
      dialogTitle: _topicThreadCreateDialogTitle(locale),
      initialTitle: initialTitle,
    );
    if (!mounted || rawTitle == null) return null;

    final created = await _topicThreadRepository.createTopicThread(
      sessionKey,
      widget.conversation.id,
      title: rawTitle.isEmpty ? null : rawTitle,
    );
    if (mounted) {
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    }
    return created;
  }

  Future<TopicThread?> _promptRenameTopicThread(
    Uint8List sessionKey,
    TopicThread target,
  ) async {
    final locale = Localizations.localeOf(context);
    final rawTitle = await _promptTopicThreadTitle(
      dialogTitle: _topicThreadRenameDialogTitle(locale),
      initialTitle: target.title,
    );
    if (!mounted || rawTitle == null) return null;

    final updated = await _topicThreadRepository.updateTopicThreadTitle(
      sessionKey,
      target.id,
      title: rawTitle.isEmpty ? null : rawTitle,
    );
    if (mounted) {
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    }
    return updated;
  }

  Future<bool> _confirmDeleteTopicThread(
    Uint8List sessionKey,
    TopicThread target,
  ) async {
    final locale = Localizations.localeOf(context);
    final title = _topicThreadDeleteDialogTitle(locale);
    final body = _topicThreadDeleteDialogBody(locale);
    final confirmLabel = _topicThreadDeleteConfirmLabel(locale);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(this.context.t.common.actions.cancel),
            ),
            TextButton(
              key: const ValueKey('topic_thread_delete_confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return false;
    final deleted = await _topicThreadRepository.deleteTopicThread(
      sessionKey,
      target.id,
    );
    if (deleted && mounted) {
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    }
    return deleted;
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
              onDeleted: () {
                _setState(() {
                  _activeTopicThreadId = null;
                  _activeTopicThread = null;
                });
                _refresh();
              },
            ),
          ),
          TextButton(
            onPressed: () {
              _setState(() {
                _activeTopicThreadId = null;
                _activeTopicThread = null;
              });
              _refresh();
            },
            child: Text(clearLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openMessageTopicThreadPicker(Message message) async {
    if (kIsWeb) return;

    final locale = Localizations.localeOf(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final threads = await _topicThreadRepository.listTopicThreads(
      sessionKey,
      widget.conversation.id,
    );
    if (!mounted) return;

    final membershipByThreadId = <String, bool>{};
    for (final thread in threads) {
      final ids = await _topicThreadRepository.listTopicThreadMessageIds(
        sessionKey,
        thread.id,
      );
      membershipByThreadId[thread.id] = ids.contains(message.id);
    }
    if (!mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final createLabel = _topicThreadCreateLabel(locale);
        final addLabel = _topicThreadAddMessageLabel(locale);
        final removeLabel = _topicThreadRemoveMessageLabel(locale);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final thread in threads)
                ListTile(
                  key: ValueKey('message_topic_thread_${thread.id}'),
                  leading: Icon(
                    membershipByThreadId[thread.id] == true
                        ? Icons.check_circle_outline_rounded
                        : Icons.add_circle_outline_rounded,
                  ),
                  title: Text(_topicThreadDisplayLabel(locale, thread)),
                  subtitle: Text(
                    membershipByThreadId[thread.id] == true
                        ? removeLabel
                        : addLabel,
                  ),
                  onTap: () => Navigator.of(context).pop(thread.id),
                ),
              ListTile(
                key: const ValueKey('message_topic_thread_create'),
                leading: const Icon(Icons.add_rounded),
                title: Text(createLabel),
                onTap: () =>
                    Navigator.of(context).pop(_kTopicThreadFilterActionCreate),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) return;

    if (selected == _kTopicThreadFilterActionCreate) {
      final created = await _promptCreateTopicThread(sessionKey);
      if (!mounted || created == null) return;
      final currentIds = await _topicThreadRepository.listTopicThreadMessageIds(
        sessionKey,
        created.id,
      );
      final next = <String>[...currentIds, message.id];
      await _topicThreadRepository.setTopicThreadMessageIds(
        sessionKey,
        created.id,
        next,
      );
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      _setState(() {
        _activeTopicThreadId = created.id;
        _activeTopicThread = created;
      });
      _refresh();
      return;
    }

    final target = _findTopicThreadById(threads, selected);
    if (target == null) return;

    final currentIds = await _topicThreadRepository.listTopicThreadMessageIds(
      sessionKey,
      target.id,
    );
    final alreadyInThread = currentIds.contains(message.id);
    final next = alreadyInThread
        ? currentIds.where((id) => id != message.id).toList(growable: false)
        : <String>[...currentIds, message.id];

    await _topicThreadRepository.setTopicThreadMessageIds(
      sessionKey,
      target.id,
      next,
    );
    if (!mounted) return;

    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    if (_activeTopicThreadId == target.id) {
      _refresh();
    }
  }
}
