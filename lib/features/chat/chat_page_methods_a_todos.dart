part of 'chat_page.dart';

extension _ChatPageStateMethodsATodos on _ChatPageState {
  Future<void> _convertMessageTodoToInfo(
      Message message, Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;

    final shouldConvert = await _showDialogFromChat<bool>(
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

    if (linkedTodo.sourceEntryId != message.id) {
      await _undoFollowupLinkForMessage(message, linkedTodo: linkedTodo);
      return;
    }

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final linkedMessageIds = <String>{message.id};
    final sourceTodos = <Todo>[];

    try {
      final todos = await backend.listTodos(sessionKey);
      for (final todo in todos) {
        if (todo.sourceEntryId == message.id) {
          sourceTodos.add(todo);
        }
      }
    } catch (_) {
      // ignore
    }
    if (sourceTodos.isEmpty) {
      sourceTodos.add(linkedTodo);
    }

    for (final sourceTodo in sourceTodos) {
      try {
        final activities = await backend.listTodoActivities(
          sessionKey,
          sourceTodo.id,
        );
        for (final activity in activities) {
          final sourceMessageId = activity.sourceMessageId?.trim();
          if (sourceMessageId == null || sourceMessageId.isEmpty) {
            continue;
          }
          linkedMessageIds.add(sourceMessageId);
        }
      } catch (_) {
        // ignore
      }

      try {
        await backend.upsertTodo(
          sessionKey,
          id: sourceTodo.id,
          title: sourceTodo.title,
          dueAtMs: null,
          status: 'dismissed',
          sourceEntryId: null,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: coerceNullablePlatformInt(sourceTodo.lastReviewAtMs),
        );
      } catch (_) {
        return;
      }
    }

    for (final linkedMessageId in linkedMessageIds) {
      try {
        await backend.markSemanticParseJobUndone(
          sessionKey,
          messageId: linkedMessageId,
          nowMs: nowMs,
        );
      } catch (_) {
        // ignore
      }
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh(refreshTaskPriority: true);
  }

  Future<void> _ensureDetachedTodoExistsForMessage(
    Message message, {
    Todo? linkedTodo,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final detachedTodoId = '$_kDetachedTodoIdPrefix${message.id}';
    final linkedTitle = linkedTodo?.title.trim() ?? '';
    final fallbackTitle = _displayTextForMessage(message).trim();
    final title = linkedTitle.isNotEmpty
        ? linkedTitle
        : fallbackTitle.isEmpty
            ? '$_kDetachedTodoTitlePrefix${message.id}'
            : '$_kDetachedTodoTitlePrefix$fallbackTitle';

    await backend.upsertTodo(
      sessionKey,
      id: detachedTodoId,
      title: title.trim(),
      dueAtMs: null,
      status: 'dismissed',
      sourceEntryId: null,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowMs,
    );
  }

  Future<void> _undoFollowupLinkForMessage(
    Message message, {
    Todo? linkedTodo,
  }) async {
    if (!mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final detachedTodoId = '$_kDetachedTodoIdPrefix${message.id}';

    try {
      await _ensureDetachedTodoExistsForMessage(
        message,
        linkedTodo: linkedTodo,
      );
    } catch (_) {
      return;
    }

    try {
      await _moveLinkedTodoActivitiesForMessage(
        messageId: message.id,
        toTodoId: detachedTodoId,
      );
    } catch (_) {
      return;
    }

    SemanticParseJob? latestFollowup;
    try {
      final jobs = await backend.listSemanticParseJobsByMessageIds(
        sessionKey,
        messageIds: <String>[message.id],
      );
      for (final job in jobs) {
        if (job.messageId != message.id) continue;
        if ((job.appliedActionKind ?? '').trim() != 'followup') continue;
        if (job.undoneAtMs != null) continue;
        final appliedTodoId = job.appliedTodoId?.trim();
        if (linkedTodo != null &&
            appliedTodoId != null &&
            appliedTodoId.isNotEmpty &&
            appliedTodoId != linkedTodo.id) {
          continue;
        }
        if (latestFollowup == null ||
            job.updatedAtMs.toInt() > latestFollowup.updatedAtMs.toInt()) {
          latestFollowup = job;
        }
      }
    } catch (_) {
      latestFollowup = null;
    }

    try {
      final todoId = latestFollowup?.appliedTodoId?.trim();
      final prevStatus = latestFollowup?.appliedPrevTodoStatus?.trim();
      if (todoId != null &&
          todoId.isNotEmpty &&
          prevStatus != null &&
          prevStatus.isNotEmpty) {
        await backend.setTodoStatus(
          sessionKey,
          todoId: todoId,
          newStatus: prevStatus,
        );
      }
    } catch (_) {
      // ignore
    }

    try {
      await backend.markSemanticParseJobUndone(
        sessionKey,
        messageId: message.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    syncEngine?.notifyLocalMutation();
    _refresh(refreshTaskPriority: true);
  }

  Future<List<TodoActivity>> _listLinkedTodoActivitiesForMessage({
    required String messageId,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return const <TodoActivity>[];

    final activities = await backend.listTodoActivitiesInRange(
      sessionKey,
      startAtMsInclusive: 0,
      endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
    );
    return activities
        .where((activity) => activity.sourceMessageId == normalizedMessageId)
        .toList(growable: false);
  }

  Future<int> _moveLinkedTodoActivitiesForMessage({
    required String messageId,
    required String toTodoId,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final normalizedTargetTodoId = toTodoId.trim();
    if (normalizedTargetTodoId.isEmpty) return 0;

    final activities = await _listLinkedTodoActivitiesForMessage(
      messageId: messageId,
    );

    var moved = 0;
    for (final activity in activities) {
      if (activity.todoId == normalizedTargetTodoId) continue;
      await backend.moveTodoActivity(
        sessionKey,
        activityId: activity.id,
        toTodoId: normalizedTargetTodoId,
      );
      moved += 1;
    }
    return moved;
  }

  Future<void> _openLinkedTodo(Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          TodoDetailPage(initialTodo: linkedTodo),
        ),
      ),
    );
  }

  Future<bool> _openTodoById(String todoId) async {
    final normalizedTodoId = todoId.trim();
    if (normalizedTodoId.isEmpty) return false;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    Todo? todo;
    try {
      todo = await backend.getTodoById(sessionKey, normalizedTodoId);
    } catch (_) {
      todo = null;
    }

    if (!mounted || todo == null) {
      return false;
    }

    await _openLinkedTodo(todo);
    return true;
  }

  Future<bool> _openEventById(String eventId) async {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty) return false;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    Event? event;
    try {
      event = await backend.getEventById(sessionKey, normalizedEventId);
    } catch (_) {
      event = null;
    }

    if (!mounted || event == null) return false;
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          EventViewerPage(event: event!),
        ),
      ),
    );
    return true;
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

    final idToken = await readCloudCapabilityIdToken(
      cloudScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );
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
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;

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

        final linkedTodos = await backend.listTodos(sessionKey);
        final todoIds = linkedTodos
            .where((todo) => todo.sourceEntryId == message.id)
            .map((todo) => todo.id)
            .toSet();
        if (todoIds.isEmpty) {
          todoIds.add(targetTodo.id);
        }

        for (final todoId in todoIds) {
          await backend.deleteTodo(sessionKey, todoId: todoId);
        }
        if (!mounted) return;
        syncEngine?.notifyLocalMutation();
        _refresh(refreshTaskPriority: true);
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
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(t.chat.deleteFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
