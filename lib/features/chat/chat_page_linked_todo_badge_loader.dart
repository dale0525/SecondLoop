part of 'chat_page.dart';

extension _ChatPageStateLinkedTodoBadgeLoader on _ChatPageState {
  Future<Map<String, _TodoMessageBadgeMeta>> _loadLinkedTodoBadgesForMessages({
    required AppBackend backend,
    required Uint8List sessionKey,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) {
      return const <String, _TodoMessageBadgeMeta>{};
    }

    final messagesById = <String, Message>{
      for (final message in messages) message.id: message,
    };

    try {
      final todos = await backend.listTodos(sessionKey);
      final byMessageId = <String, _TodoMessageBadgeMeta>{};
      final todosById = <String, Todo>{for (final todo in todos) todo.id: todo};

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
        if (byMessageId.containsKey(sourceMessageId)) continue;
        final todo = todosById[activity.todoId];
        if (todo == null) continue;
        byMessageId[sourceMessageId] = _TodoMessageBadgeMeta(
          todoId: todo.id,
          todoTitle: todo.title,
          isRelated: true,
        );
      }

      return byMessageId;
    } catch (_) {
      return const <String, _TodoMessageBadgeMeta>{};
    }
  }
}
