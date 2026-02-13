part of 'chat_page.dart';

const _kCloudDetachedRequestIdPayloadKey = 'secondloop_cloud_request_id';
final RegExp _kCloudDetachedRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9:_-]{5,127}$',
);

extension _ChatPageStateMethodsA on _ChatPageState {
  bool _isTransientPendingMessage(Message message) =>
      message.id.startsWith('pending_') && message.id != _kFailedAskMessageId;

  Future<void> _loadEmbeddingsDataConsentPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kEmbeddingsDataConsentPrefsKey)) return;

    final value = prefs.getBool(_kEmbeddingsDataConsentPrefsKey) ?? false;
    if (!mounted) return;
    _setState(() => _cloudEmbeddingsConsented = value);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels <= _kBottomThresholdPx;
    final shouldRefreshOnReturnToBottom =
        atBottom && !_isAtBottom && _hasUnseenNewMessages;
    if (atBottom != _isAtBottom) {
      _setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _hasUnseenNewMessages = false;
      });
      if (shouldRefreshOnReturnToBottom) {
        _refresh();
      }
    }

    if (!_usePagination) return;

    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining > _kLoadMoreThresholdPx) return;
    unawaited(_loadOlderMessages());
  }

  void _attachSyncEngine() {
    final engine = SyncEngineScope.maybeOf(context);
    if (identical(engine, _syncEngine)) return;

    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }

    _syncEngine = engine;
    if (engine == null) {
      _syncListener = null;
      return;
    }

    void onSyncChange() {
      if (!mounted) return;
      if (!_isAtBottom) {
        _setState(() {
          _hasUnseenNewMessages = true;
          _reviewCountFuture = _loadReviewQueueCount();
          _agendaFuture = _loadTodoAgendaSummary();
        });
        return;
      }
      _refresh();
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<void> _showMessageActions(Message message) async {
    if (_isTransientPendingMessage(message)) return;
    final isFailedAskMessage = message.id == _kFailedAskMessageId;
    if (isFailedAskMessage) {
      final action = await showModalBottomSheet<_MessageAction>(
        context: context,
        builder: (context) {
          final tokens = SlTokens.of(context);
          final colorScheme = Theme.of(context).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SlSurface(
                key: const ValueKey('message_actions_sheet'),
                color: tokens.surface2,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  key: const ValueKey('message_action_delete'),
                  leading: const Icon(Icons.delete_outline_rounded),
                  iconColor: colorScheme.error,
                  textColor: colorScheme.error,
                  title: Text(context.t.common.actions.delete),
                  onTap: () => Navigator.of(context).pop(_MessageAction.delete),
                ),
              ),
            ),
          );
        },
      );
      if (!mounted) return;
      if (action == _MessageAction.delete) {
        await _deleteMessage(message);
      }
      return;
    }

    final canEdit = await _canEditMessage(message);
    final displayText = _displayTextForMessage(message).trim();
    if (!mounted) return;

    ({Todo todo, bool isSourceEntry})? linkedTodo;
    final linkedTodoFuture = _resolveLinkedTodoInfo(message).then((value) {
      linkedTodo = value;
      return value;
    });

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) {
        final tokens = SlTokens.of(context);
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              key: const ValueKey('message_actions_sheet'),
              color: tokens.surface2,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: FutureBuilder<({Todo todo, bool isSourceEntry})?>(
                future: linkedTodoFuture,
                builder: (context, snapshot) {
                  final resolvedTodo =
                      snapshot.connectionState == ConnectionState.done
                          ? snapshot.data
                          : null;
                  final canConvertToTodo = resolvedTodo == null &&
                      displayText.isNotEmpty &&
                      snapshot.connectionState == ConnectionState.done;

                  final showLinkTodo = resolvedTodo == null ||
                      resolvedTodo.isSourceEntry == false;
                  final linkTodoTitle = resolvedTodo == null
                      ? context.t.actions.todoNoteLink.action
                      : context.t.chat.messageActions.linkOtherTodo;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        key: const ValueKey('message_action_copy'),
                        leading: const Icon(Icons.copy_all_rounded),
                        title: Text(context.t.common.actions.copy),
                        onTap: () =>
                            Navigator.of(context).pop(_MessageAction.copy),
                      ),
                      if (snapshot.connectionState == ConnectionState.done) ...[
                        if (canConvertToTodo)
                          ListTile(
                            key: const ValueKey('message_action_convert_todo'),
                            leading: const Icon(Icons.task_alt_rounded),
                            title: Text(
                                context.t.chat.messageActions.convertToTodo),
                            onTap: () => Navigator.of(context)
                                .pop(_MessageAction.convertTodo),
                          )
                        else if (resolvedTodo != null) ...[
                          ListTile(
                            key: const ValueKey('message_action_open_todo'),
                            leading: const Icon(Icons.chevron_right_rounded),
                            title: Text(context.t.chat.messageActions.openTodo),
                            onTap: () => Navigator.of(context)
                                .pop(_MessageAction.openTodo),
                          ),
                          if (resolvedTodo.isSourceEntry)
                            ListTile(
                              key: const ValueKey(
                                  'message_action_convert_to_info'),
                              leading: const Icon(Icons.undo_rounded),
                              title: Text(context
                                  .t.chat.messageActions.convertTodoToInfo),
                              onTap: () => Navigator.of(context)
                                  .pop(_MessageAction.convertTodoToInfo),
                            ),
                        ],
                      ],
                      if (canEdit)
                        ListTile(
                          key: const ValueKey('message_action_edit'),
                          leading: const Icon(Icons.edit_rounded),
                          title: Text(context.t.common.actions.edit),
                          onTap: () =>
                              Navigator.of(context).pop(_MessageAction.edit),
                        ),
                      if (showLinkTodo)
                        ListTile(
                          key: const ValueKey('message_action_link_todo'),
                          leading: const Icon(Icons.link_rounded),
                          title: Text(linkTodoTitle),
                          onTap: () => Navigator.of(context)
                              .pop(_MessageAction.linkTodo),
                        ),
                      ListTile(
                        key: const ValueKey('message_action_delete'),
                        leading: const Icon(Icons.delete_outline_rounded),
                        iconColor: colorScheme.error,
                        textColor: colorScheme.error,
                        title: Text(context.t.common.actions.delete),
                        onTap: () =>
                            Navigator.of(context).pop(_MessageAction.delete),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
        break;
      case null:
        break;
    }
  }

  String _displayTextForMessage(Message message) {
    final raw = message.content;
    final actions =
        message.role == 'assistant' ? parseAssistantMessageActions(raw) : null;
    final text = (actions?.displayText ?? raw).trim();
    if (text == 'Photo' || text == '照片') return '';
    return text;
  }

  bool _isPhotoPlaceholderText(BuildContext context, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final localized = context.t.chat.photoMessage.trim();
    if (localized.isNotEmpty && trimmed == localized) return true;
    return trimmed == 'Photo' || trimmed == '照片';
  }

  Future<void> _copyMessageToClipboard(Message message) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: _displayTextForMessage(message)),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.actions.history.actions.copied),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pasteIntoChatInput() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;
    if (text == null || text.isEmpty) return;

    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;
    _controller.value = value.copyWith(
      text: value.text.replaceRange(normalizedStart, normalizedEnd, text),
      selection: TextSelection.collapsed(offset: normalizedStart + text.length),
      composing: TextRange.empty,
    );
  }

  bool _shouldCollapseMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.runes.length >= _kLongMessageRuneThreshold) return true;
    final lineCount = '\n'.allMatches(trimmed).length + 1;
    if (lineCount >= _kLongMessageLineThreshold) return true;
    return false;
  }

  Widget _buildMessageMarkdown(
    String content, {
    required bool isDesktopPlatform,
  }) {
    final normalized = sanitizeChatMarkdown(content);
    final markdown = MarkdownBody(
      data: normalized,
      selectable: false,
      styleSheet: slMarkdownStyleSheet(context),
    );
    if (!isDesktopPlatform) return markdown;

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) =>
          const SizedBox.shrink(),
      child: markdown,
    );
  }

  Future<void> _openMessageViewer(String content) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            MessageViewerPage(content: sanitizeChatMarkdown(content)),
      ),
    );
  }

  Future<void> _showMessageContextMenu(
    Message message,
    Offset globalPosition,
  ) async {
    if (_isTransientPendingMessage(message)) return;
    final isFailedAskMessage = message.id == _kFailedAskMessageId;
    if (isFailedAskMessage) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final action = await showMenu<_MessageAction>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_delete'),
            value: _MessageAction.delete,
            child: Text(context.t.common.actions.delete),
          ),
        ],
      );
      if (!mounted) return;
      if (action == _MessageAction.delete) {
        await _deleteMessage(message);
      }
      return;
    }

    final canEdit = await _canEditMessage(message);
    final linkedTodo = await _resolveLinkedTodoInfo(message);
    final canConvertToTodo =
        linkedTodo == null && _displayTextForMessage(message).trim().isNotEmpty;
    if (!mounted) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_MessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_copy'),
          value: _MessageAction.copy,
          child: Text(context.t.common.actions.copy),
        ),
        if (canConvertToTodo)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_todo'),
            value: _MessageAction.convertTodo,
            child: Text(context.t.chat.messageActions.convertToTodo),
          )
        else if (linkedTodo != null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_open_todo'),
            value: _MessageAction.openTodo,
            child: Text(context.t.chat.messageActions.openTodo),
          ),
        if (linkedTodo != null && linkedTodo.isSourceEntry)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_to_info'),
            value: _MessageAction.convertTodoToInfo,
            child: Text(context.t.chat.messageActions.convertTodoToInfo),
          ),
        if (canEdit)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_edit'),
            value: _MessageAction.edit,
            child: Text(context.t.common.actions.edit),
          ),
        if (linkedTodo == null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.actions.todoNoteLink.action),
          )
        else if (!linkedTodo.isSourceEntry)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.chat.messageActions.linkOtherTodo),
          ),
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_delete'),
          value: _MessageAction.delete,
          child: Text(context.t.common.actions.delete),
        ),
      ],
    );
    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
        break;
      case null:
        break;
    }
  }

  Future<({Todo todo, bool isSourceEntry})?> _resolveLinkedTodoInfo(
    Message message,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return null;
    }

    final todosById = <String, Todo>{};
    for (final todo in todos) {
      todosById[todo.id] = todo;
      if (todo.sourceEntryId == message.id) {
        return (todo: todo, isSourceEntry: true);
      }
    }

    try {
      final activities = await backend.listTodoActivitiesInRange(
        sessionKey,
        startAtMsInclusive: 0,
        endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
      );
      for (final activity in activities) {
        if (activity.sourceMessageId != message.id) continue;
        final todo = todosById[activity.todoId];
        if (todo != null) return (todo: todo, isSourceEntry: false);
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<void> _convertMessageToTodo(Message message) async {
    if (!mounted) return;

    final rawText = _displayTextForMessage(message);
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final todoId = 'todo:${message.id}';

    final locale = Localizations.localeOf(context);
    final settings = await ActionsSettingsStore.load();
    if (!mounted) return;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      trimmed,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );

    DateTime? dueAtLocal;
    final candidates = timeResolution?.candidates ?? const <DueCandidate>[];
    if (candidates.isNotEmpty) {
      dueAtLocal = candidates.first.dueAtLocal;
    } else {
      final initialLocal = DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        settings.dayEndTime.hour,
        settings.dayEndTime.minute,
      );
      dueAtLocal = await showSlDateTimePickerDialog(
        context,
        initialLocal: initialLocal,
        firstDate: DateTime(nowLocal.year - 1),
        lastDate: DateTime(nowLocal.year + 3),
        title: context.t.actions.calendar.pickCustom,
        surfaceKey: ValueKey('message_convert_todo_due_picker_${message.id}'),
      );
    }

    if (dueAtLocal == null || !mounted) return;

    try {
      await backend.upsertTodo(
        sessionKey,
        id: todoId,
        title: trimmed,
        dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
        status: 'open',
        sourceEntryId: message.id,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh();
  }

  Future<void> _convertMessageTodoToInfo(
      Message message, Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (linkedTodo.sourceEntryId != message.id) return;
    if (!mounted) return;

    final shouldConvert = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmTitle),
          content:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmBody),
          actions: [
            SlButton(
              variant: SlButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            SlButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.common.fields.confirm),
            ),
          ],
        );
      },
    );
    if (shouldConvert != true || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    try {
      await backend.upsertTodo(
        sessionKey,
        id: linkedTodo.id,
        title: linkedTodo.title,
        dueAtMs: null,
        status: 'dismissed',
        sourceEntryId: null,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: linkedTodo.lastReviewAtMs,
      );
    } catch (_) {
      return;
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh();
  }

  Future<void> _openLinkedTodo(Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TodoDetailPage(initialTodo: linkedTodo),
      ),
    );
  }

  Future<void> _editMessage(Message message) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);

    var draft = message.content;
    try {
      final newContent = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(context.t.chat.editMessageTitle),
            content: TextFormField(
              key: const ValueKey('edit_message_content'),
              initialValue: draft,
              autofocus: true,
              maxLines: null,
              onChanged: (value) => draft = value,
            ),
            actions: [
              SlButton(
                variant: SlButtonVariant.outline,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t.common.actions.cancel),
              ),
              SlButton(
                buttonKey: const ValueKey('edit_message_save'),
                icon: const Icon(Icons.save_rounded, size: 18),
                variant: SlButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(draft),
                child: Text(context.t.common.actions.save),
              ),
            ],
          );
        },
      );

      final trimmed = newContent?.trim();
      if (trimmed == null) return;

      await backend.editMessage(sessionKey, message.id, trimmed);
      try {
        await backend.markSemanticParseJobCanceled(
          sessionKey,
          messageId: message.id,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        // ignore
      }
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.messageUpdated),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.editFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String? _extractCloudDetachedRequestIdFromPayloadJson(String? payloadJson) {
    final raw = payloadJson?.trim() ?? '';
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final requestId =
          (decoded[_kCloudDetachedRequestIdPayloadKey] ?? '').toString().trim();
      if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId)) {
        return null;
      }
      return requestId;
    } catch (_) {
      return null;
    }
  }

  Uri? _buildCloudDetachedCancelUri(String gatewayBaseUrl, String requestId) {
    final base = gatewayBaseUrl.trim();
    final normalizedRequestId = requestId.trim();
    if (base.isEmpty || normalizedRequestId.isEmpty) return null;

    final normalizedBase = base.replaceFirst(RegExp(r'/+$'), '');
    try {
      return Uri.parse(
        '$normalizedBase/v1/chat/jobs/$normalizedRequestId/cancel',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cancelCloudDetachedChatJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId.trim())) {
      return;
    }
    final uri = _buildCloudDetachedCancelUri(gatewayBaseUrl, requestId);
    if (uri == null) return;

    final token = idToken.trim();
    if (token.isEmpty) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _bestEffortCancelCloudMediaJobsForMessage({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String messageId,
  }) async {
    final cloudScope = CloudAuthScope.maybeOf(context);
    final gatewayBaseUrl = (cloudScope?.gatewayConfig.baseUrl ?? '').trim();
    if (gatewayBaseUrl.isEmpty) return;

    String? idToken;
    try {
      idToken = await cloudScope?.controller.getIdToken();
    } catch (_) {
      idToken = null;
    }
    if ((idToken ?? '').trim().isEmpty) return;

    if (backend is! NativeAppBackend) return;

    List<Attachment> attachments;
    try {
      attachments = await backend.listMessageAttachments(
        sessionKey,
        messageId,
      );
    } catch (_) {
      return;
    }

    if (attachments.isEmpty) return;

    final requestIds = <String>{};
    for (final attachment in attachments) {
      try {
        final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
          sessionKey,
          sha256: attachment.sha256,
        );
        final requestId =
            _extractCloudDetachedRequestIdFromPayloadJson(payloadJson);
        if (requestId == null) continue;
        requestIds.add(requestId);
      } catch (_) {
        // ignore per-attachment parse failures
      }
    }

    if (requestIds.isEmpty) return;

    for (final requestId in requestIds) {
      try {
        await _cancelCloudDetachedChatJob(
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: idToken!,
          requestId: requestId,
        );
      } catch (_) {
        // best-effort only
      }
    }
  }

  Future<void> _deleteMessage(
    Message message, {
    ({Todo todo, bool isSourceEntry})? linkedTodoInfo,
  }) async {
    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);

      if (message.id == _kFailedAskMessageId) {
        final confirmed = await showSlDeleteConfirmDialog(
          context,
          title: t.chat.deleteMessageDialog.title,
          message: t.chat.deleteMessageDialog.message,
          confirmButtonKey: const ValueKey('chat_delete_message_confirm'),
        );
        if (!mounted) return;
        if (!confirmed) return;

        _setState(() {
          _askFailureQuestion = null;
          _askFailureMessage = null;
          _askFailureCreatedAtMs = null;
          _askFailureAnchorMessageId = null;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.chat.messageDeleted),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      var resolvedLinkedTodoInfo = linkedTodoInfo;
      if (resolvedLinkedTodoInfo == null) {
        resolvedLinkedTodoInfo = await _resolveLinkedTodoInfo(message);
        if (!mounted) return;
      }

      final targetTodo = resolvedLinkedTodoInfo?.todo;
      final isSourceEntry = resolvedLinkedTodoInfo?.isSourceEntry == true;
      if (targetTodo != null && isSourceEntry) {
        final confirmed = await showSlDeleteConfirmDialog(
          context,
          title: t.actions.todoDelete.dialog.title,
          message: t.actions.todoDelete.dialog.message,
          confirmLabel: t.actions.todoDelete.dialog.confirm,
          confirmButtonKey: const ValueKey('chat_delete_todo_confirm'),
        );
        if (!mounted) return;
        if (!confirmed) return;

        await backend.deleteTodo(sessionKey, todoId: targetTodo.id);
        if (!mounted) return;
        syncEngine?.notifyLocalMutation();
        _refresh();
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.chat.messageDeleted),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final confirmed = await showSlDeleteConfirmDialog(
        context,
        title: t.chat.deleteMessageDialog.title,
        message: t.chat.deleteMessageDialog.message,
        confirmButtonKey: const ValueKey('chat_delete_message_confirm'),
      );
      if (!mounted) return;
      if (!confirmed) return;

      await _bestEffortCancelCloudMediaJobsForMessage(
        backend: backend,
        sessionKey: sessionKey,
        messageId: message.id,
      );
      await backend.purgeMessageAttachments(sessionKey, message.id);
      try {
        await backend.markSemanticParseJobCanceled(
          sessionKey,
          messageId: message.id,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        // ignore
      }
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(t.chat.messageDeleted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.chat.deleteFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
