part of 'chat_page.dart';

extension _ChatPageStateLinkedTodoBadgeLoader on _ChatPageState {
  Future<
      ({
        Map<String, _TodoMessageBadgeMeta> badges,
        Set<String> existingTodoIds,
      })> _loadLinkedTodoBadgesForMessages({
    required AppBackend backend,
    required Uint8List sessionKey,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) {
      return (
        badges: const <String, _TodoMessageBadgeMeta>{},
        existingTodoIds: const <String>{},
      );
    }

    final messagesById = <String, Message>{
      for (final message in messages) message.id: message,
    };

    try {
      final todos = await backend.listTodos(sessionKey);
      final byMessageId = <String, _TodoMessageBadgeMeta>{};
      final todosById = <String, Todo>{for (final todo in todos) todo.id: todo};
      final existingTodoIds = todosById.keys.toSet();
      final messageIds = messagesById.keys.toList(growable: false);
      var semanticParseConsented = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        semanticParseConsented =
            SemanticParseDataConsentPrefs.readEffectiveEnabled(prefs);
      } catch (_) {
        semanticParseConsented = false;
      }

      final undoneFollowupCutoffByMessageId = <String, int>{};
      if (semanticParseConsented && messageIds.isNotEmpty) {
        try {
          final jobs = await backend.listSemanticParseJobsByMessageIds(
            sessionKey,
            messageIds: messageIds,
          );
          for (final job in jobs) {
            if ((job.appliedActionKind ?? '').trim() != 'followup') continue;
            final undoneAtMs = job.undoneAtMs?.toInt();
            if (undoneAtMs == null) continue;
            final currentCutoff =
                undoneFollowupCutoffByMessageId[job.messageId];
            if (currentCutoff == null || undoneAtMs > currentCutoff) {
              undoneFollowupCutoffByMessageId[job.messageId] = undoneAtMs;
            }
          }
        } catch (_) {
          undoneFollowupCutoffByMessageId.clear();
        }
      }

      for (final todo in todos) {
        final sourceMessageId = todo.sourceEntryId?.trim();
        if (sourceMessageId == null || sourceMessageId.isEmpty) continue;
        if (!messagesById.containsKey(sourceMessageId)) continue;
        byMessageId[sourceMessageId] = _TodoMessageBadgeMeta(
          todoId: todo.id,
          todoTitle: todo.title,
          isRelated: false,
        );
      }

      final activities = await backend.listTodoActivitiesInRange(
        sessionKey,
        startAtMsInclusive: 0,
        endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
      );

      for (final activity in activities) {
        final sourceMessageId = activity.sourceMessageId?.trim();
        if (sourceMessageId == null || sourceMessageId.isEmpty) continue;
        if (!messagesById.containsKey(sourceMessageId)) continue;
        final cutoffMs = undoneFollowupCutoffByMessageId[sourceMessageId];
        if (cutoffMs != null &&
            activity.activityType == 'status_change' &&
            activity.createdAtMs.toInt() <= cutoffMs) {
          continue;
        }
        if (byMessageId.containsKey(sourceMessageId)) continue;
        final todo = todosById[activity.todoId];
        if (todo == null || todo.status == 'dismissed') continue;
        byMessageId[sourceMessageId] = _TodoMessageBadgeMeta(
          todoId: todo.id,
          todoTitle: todo.title,
          isRelated: true,
        );
      }

      return (badges: byMessageId, existingTodoIds: existingTodoIds);
    } catch (_) {
      return (
        badges: const <String, _TodoMessageBadgeMeta>{},
        existingTodoIds: const <String>{},
      );
    }
  }
}
