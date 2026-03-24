part of 'cloud_web_backend.dart';

mixin _CloudWebBackendTasksMixin
    on AppBackend, _CloudWebBackendTasksRecurrenceMixin {
  @override
  final Map<String, Todo> _todosById = <String, Todo>{};
  final Map<String, TodoActivity> _todoActivitiesById =
      <String, TodoActivity>{};
  final Map<String, List<TodoChecklistItem>> _checklistItemsByTodoId =
      <String, List<TodoChecklistItem>>{};
  final Map<String, List<TodoChecklistSuggestion>>
      _todoChecklistSuggestionsByTodoId =
      <String, List<TodoChecklistSuggestion>>{};
  final Map<String, List<String>> _attachmentShasByTodoActivityId =
      <String, List<String>>{};
  @override
  String _nextId(String prefix);
  @override
  int _touchNow();
  @override
  PlatformInt64 _asPlatformInt64(int value);
  Map<String, Attachment> get _attachmentsBySha;

  int _compareTodoOrder(Todo left, Todo right) {
    final leftDueAtMs = left.dueAtMs;
    final rightDueAtMs = right.dueAtMs;
    if (leftDueAtMs == null && rightDueAtMs != null) {
      return 1;
    }
    if (leftDueAtMs != null && rightDueAtMs == null) {
      return -1;
    }
    if (leftDueAtMs != null && rightDueAtMs != null) {
      final byDueAt = leftDueAtMs.compareTo(rightDueAtMs);
      if (byDueAt != 0) {
        return byDueAt;
      }
    }
    final byCreatedAt = left.createdAtMs.compareTo(right.createdAtMs);
    if (byCreatedAt != 0) {
      return byCreatedAt;
    }
    return left.id.compareTo(right.id);
  }

  List<TodoChecklistItem> _checklistBucket(String todoId) {
    return _checklistItemsByTodoId.putIfAbsent(
      todoId,
      () => <TodoChecklistItem>[],
    );
  }

  List<TodoChecklistSuggestion> _suggestionBucket(String todoId) {
    return _todoChecklistSuggestionsByTodoId.putIfAbsent(
      todoId,
      () => <TodoChecklistSuggestion>[],
    );
  }

  List<TodoChecklistSuggestion> _sortedSuggestions(
    Iterable<TodoChecklistSuggestion> suggestions,
  ) {
    final copy = suggestions.toList(growable: false)
      ..sort(
        (left, right) {
          final byOrder = left.sortOrder.compareTo(right.sortOrder);
          if (byOrder != 0) {
            return byOrder;
          }
          return left.id.compareTo(right.id);
        },
      );
    return copy;
  }

  String _normalizeChecklistSuggestionContent(String content) {
    return content
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ')
        .toLowerCase();
  }

  List<TodoActivity> _sortedActivities(Iterable<TodoActivity> activities) {
    final copy = activities.toList(growable: false)
      ..sort(
        (left, right) {
          final byCreatedAt = left.createdAtMs.compareTo(right.createdAtMs);
          if (byCreatedAt != 0) {
            return byCreatedAt;
          }
          return left.id.compareTo(right.id);
        },
      );
    return copy;
  }

  TodoActivity _recordStatusChangeActivity({
    required Todo existing,
    required String newStatus,
    String? sourceMessageId,
  }) {
    final activity = TodoActivity(
      id: _nextId('activity'),
      todoId: existing.id,
      activityType: 'status_change',
      fromStatus: existing.status,
      toStatus: newStatus,
      sourceMessageId: sourceMessageId,
      createdAtMs: _asPlatformInt64(_touchNow()),
    );
    _todoActivitiesById[activity.id] = activity;
    return activity;
  }

  TodoChecklistItem _findChecklistItem(String itemId) {
    for (final items in _checklistItemsByTodoId.values) {
      for (final item in items) {
        if (item.id == itemId) {
          return item;
        }
      }
    }
    throw StateError('unknown_checklist_item:$itemId');
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    final todos = _todosById.values.toList(growable: false)
      ..sort(_compareTodoOrder);
    return todos;
  }

  @override
  Future<List<Todo>> listTodosCreatedInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    return (await listTodos(key))
        .where(
          (todo) =>
              todo.createdAtMs >= startAtMsInclusive &&
              todo.createdAtMs < endAtMsExclusive,
        )
        .toList(growable: false);
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    final now = _touchNow();
    final existing = _todosById[id];
    final targetManualImportanceNudgeScore = manualImportanceNudgeScore ??
        (existing?.manualImportanceNudgeScore ?? 0);
    final targetManualUrgencyNudgeScore =
        manualUrgencyNudgeScore ?? (existing?.manualUrgencyNudgeScore ?? 0);
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
      reviewStage: reviewStage == null ? null : _asPlatformInt64(reviewStage),
      nextReviewAtMs:
          nextReviewAtMs == null ? null : _asPlatformInt64(nextReviewAtMs),
      lastReviewAtMs:
          lastReviewAtMs == null ? null : _asPlatformInt64(lastReviewAtMs),
      manualImportanceNudgeScore:
          _asPlatformInt64(targetManualImportanceNudgeScore.clamp(-1, 1)),
      manualUrgencyNudgeScore:
          _asPlatformInt64(targetManualUrgencyNudgeScore.clamp(-1, 1)),
    );
    _todosById[id] = todo;
    return todo;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('unknown_todo:$todoId');
    }
    if (newStatus == existing.status) {
      return existing;
    }

    final now = _touchNow();
    final targetReviewStage = existing.status == 'inbox' && newStatus != 'inbox'
        ? null
        : existing.reviewStage;
    final targetNextReviewAtMs =
        existing.status == 'inbox' && newStatus != 'inbox'
            ? null
            : existing.nextReviewAtMs;
    final targetDueAtMs = existing.dueAtMs == null &&
            existing.status == 'open' &&
            (newStatus == 'in_progress' || newStatus == 'done')
        ? now
        : existing.dueAtMs;
    final updated = await upsertTodo(
      key,
      id: existing.id,
      title: existing.title,
      dueAtMs: targetDueAtMs,
      status: newStatus,
      sourceEntryId: existing.sourceEntryId,
      reviewStage: targetReviewStage,
      nextReviewAtMs: targetNextReviewAtMs,
      lastReviewAtMs: now,
      manualImportanceNudgeScore: existing.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: existing.manualUrgencyNudgeScore,
    );
    _recordStatusChangeActivity(
      existing: existing,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
    );
    return updated;
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('unknown_todo:$todoId');
    }

    final staged = newStatus != null && newStatus != existing.status
        ? await setTodoStatus(
            key,
            todoId: todoId,
            newStatus: newStatus,
            sourceMessageId: sourceMessageId,
          )
        : existing;

    final targetDueAtMs = clearDueAtMs ? null : (dueAtMs ?? staged.dueAtMs);
    final targetReviewStage =
        clearReviewStage ? null : (reviewStage ?? staged.reviewStage);
    final targetNextReviewAtMs =
        clearNextReviewAtMs ? null : (nextReviewAtMs ?? staged.nextReviewAtMs);
    final targetLastReviewAtMs =
        clearLastReviewAtMs ? null : (lastReviewAtMs ?? staged.lastReviewAtMs);
    final targetManualImportanceNudgeScore = clearManualImportanceNudgeScore
        ? 0
        : (manualImportanceNudgeScore ??
            (staged.manualImportanceNudgeScore ?? 0));
    final targetManualUrgencyNudgeScore = clearManualUrgencyNudgeScore
        ? 0
        : (manualUrgencyNudgeScore ?? (staged.manualUrgencyNudgeScore ?? 0));

    if (targetDueAtMs == staged.dueAtMs &&
        targetReviewStage == staged.reviewStage &&
        targetNextReviewAtMs == staged.nextReviewAtMs &&
        targetLastReviewAtMs == staged.lastReviewAtMs &&
        targetManualImportanceNudgeScore ==
            (staged.manualImportanceNudgeScore ?? 0) &&
        targetManualUrgencyNudgeScore ==
            (staged.manualUrgencyNudgeScore ?? 0)) {
      return staged;
    }

    return upsertTodo(
      key,
      id: staged.id,
      title: staged.title,
      dueAtMs: targetDueAtMs,
      status: staged.status,
      sourceEntryId: staged.sourceEntryId,
      reviewStage: targetReviewStage,
      nextReviewAtMs: targetNextReviewAtMs,
      lastReviewAtMs: targetLastReviewAtMs,
      manualImportanceNudgeScore: targetManualImportanceNudgeScore,
      manualUrgencyNudgeScore: targetManualUrgencyNudgeScore,
    );
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    _todosById.remove(todoId);
    _checklistItemsByTodoId.remove(todoId);
    _todoChecklistSuggestionsByTodoId.remove(todoId);
    _todoRecurrenceRuleJsonByTodoId.remove(todoId);
    _todoRecurrenceSeriesIdByTodoId.remove(todoId);
    _todoRecurrenceOccurrenceIndexByTodoId.remove(todoId);
    final removedActivityIds = _todoActivitiesById.values
        .where((activity) => activity.todoId == todoId)
        .map((activity) => activity.id)
        .toList(growable: false);
    _todoActivitiesById.removeWhere((_, activity) => activity.todoId == todoId);
    for (final activityId in removedActivityIds) {
      _attachmentShasByTodoActivityId.remove(activityId);
    }
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    final todo = _todosById[todoId];
    if (todo == null) {
      throw StateError('unknown_todo:$todoId');
    }
    String? resolvedSourceMessageId = sourceMessageId?.trim();
    final nowMs = _touchNow();
    var createdAtMs = nowMs;

    if (resolvedSourceMessageId == null || resolvedSourceMessageId.isEmpty) {
      String? conversationId;
      final sourceEntryId = todo.sourceEntryId?.trim();
      if (sourceEntryId != null && sourceEntryId.isNotEmpty) {
        final sourceMessage = await getMessageById(key, sourceEntryId);
        final sourceConversationId = sourceMessage?.conversationId.trim();
        if (sourceConversationId != null && sourceConversationId.isNotEmpty) {
          conversationId = sourceConversationId;
        }
      }

      if (conversationId == null) {
        final loopHome = await getOrCreateLoopHomeConversation(key);
        conversationId = loopHome.id;
      }

      final createdMessage = await insertMessage(
        key,
        conversationId,
        role: 'user',
        content: content,
      );
      resolvedSourceMessageId = createdMessage.id;
      createdAtMs = createdMessage.createdAtMs.toInt();
    } else {
      final existingMessage =
          await getMessageById(key, resolvedSourceMessageId);
      if (existingMessage != null) {
        createdAtMs = existingMessage.createdAtMs.toInt();
      }
    }

    final activity = TodoActivity(
      id: _nextId('activity'),
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: resolvedSourceMessageId,
      createdAtMs: _asPlatformInt64(createdAtMs),
    );
    _todoActivitiesById[activity.id] = activity;
    return activity;
  }

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    final existing = _todoActivitiesById[activityId];
    if (existing == null) {
      throw StateError('unknown_todo_activity:$activityId');
    }
    final moved = TodoActivity(
      id: existing.id,
      todoId: toTodoId,
      activityType: existing.activityType,
      fromStatus: existing.fromStatus,
      toStatus: existing.toStatus,
      content: existing.content,
      sourceMessageId: existing.sourceMessageId,
      createdAtMs: existing.createdAtMs,
    );
    _todoActivitiesById[activityId] = moved;
    return moved;
  }

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async {
    final items = List<TodoChecklistItem>.of(_checklistBucket(todoId))
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return items;
  }

  @override
  Future<TodoChecklistItem> createTodoChecklistItem(
    Uint8List key, {
    required String todoId,
    required String content,
  }) async {
    if (!_todosById.containsKey(todoId)) {
      throw StateError('unknown_todo:$todoId');
    }
    final now = _touchNow();
    final bucket = _checklistBucket(todoId);
    final item = TodoChecklistItem(
      id: _nextId('checklist'),
      todoId: todoId,
      content: content,
      sortOrder: bucket.length,
      isDone: false,
      createdAtMs: _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
    );
    bucket.add(item);
    return item;
  }

  @override
  Future<TodoChecklistItem> updateTodoChecklistItemContent(
    Uint8List key, {
    required String itemId,
    required String content,
  }) async {
    final existing = _findChecklistItem(itemId);
    final now = _touchNow();
    final updated = TodoChecklistItem(
      id: existing.id,
      todoId: existing.todoId,
      content: content,
      sortOrder: existing.sortOrder,
      isDone: existing.isDone,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: _asPlatformInt64(now),
    );
    final bucket = _checklistBucket(existing.todoId);
    final index = bucket.indexWhere((item) => item.id == itemId);
    bucket[index] = updated;
    return updated;
  }

  @override
  Future<TodoChecklistItem> setTodoChecklistItemDone(
    Uint8List key, {
    required String itemId,
    required bool isDone,
  }) async {
    final existing = _findChecklistItem(itemId);
    final now = _touchNow();
    final updated = TodoChecklistItem(
      id: existing.id,
      todoId: existing.todoId,
      content: existing.content,
      sortOrder: existing.sortOrder,
      isDone: isDone,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: _asPlatformInt64(now),
    );
    final bucket = _checklistBucket(existing.todoId);
    final index = bucket.indexWhere((item) => item.id == itemId);
    bucket[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodoChecklistItem(
    Uint8List key, {
    required String itemId,
  }) async {
    for (final entry in _checklistItemsByTodoId.entries) {
      final index = entry.value.indexWhere((item) => item.id == itemId);
      if (index < 0) continue;
      entry.value.removeAt(index);
      for (var i = 0; i < entry.value.length; i += 1) {
        final current = entry.value[i];
        entry.value[i] = TodoChecklistItem(
          id: current.id,
          todoId: current.todoId,
          content: current.content,
          sortOrder: i,
          isDone: current.isDone,
          createdAtMs: current.createdAtMs,
          updatedAtMs: current.updatedAtMs,
        );
      }
      return;
    }
  }

  @override
  Future<void> reorderTodoChecklistItems(
    Uint8List key, {
    required String todoId,
    required List<String> orderedItemIds,
  }) async {
    final bucket = _checklistBucket(todoId);
    if (orderedItemIds.isEmpty) return;
    final byId = <String, TodoChecklistItem>{
      for (final item in bucket) item.id: item,
    };
    final reordered = <TodoChecklistItem>[];
    for (var i = 0; i < orderedItemIds.length; i += 1) {
      final item = byId[orderedItemIds[i]];
      if (item == null) {
        throw StateError('unknown_checklist_item:${orderedItemIds[i]}');
      }
      reordered.add(
        TodoChecklistItem(
          id: item.id,
          todoId: item.todoId,
          content: item.content,
          sortOrder: i,
          isDone: item.isDone,
          createdAtMs: item.createdAtMs,
          updatedAtMs: item.updatedAtMs,
        ),
      );
    }
    final specifiedIds = orderedItemIds.toSet();
    final remaining = bucket
        .where((item) => !specifiedIds.contains(item.id))
        .toList(growable: false)
      ..sort((left, right) {
        final byOrder = left.sortOrder.compareTo(right.sortOrder);
        if (byOrder != 0) {
          return byOrder;
        }
        final byCreatedAt = left.createdAtMs.compareTo(right.createdAtMs);
        if (byCreatedAt != 0) {
          return byCreatedAt;
        }
        return left.id.compareTo(right.id);
      });
    for (final item in remaining) {
      reordered.add(
        TodoChecklistItem(
          id: item.id,
          todoId: item.todoId,
          content: item.content,
          sortOrder: reordered.length,
          isDone: item.isDone,
          createdAtMs: item.createdAtMs,
          updatedAtMs: item.updatedAtMs,
        ),
      );
    }
    bucket
      ..clear()
      ..addAll(reordered);
  }

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async {
    final progress = <TodoChecklistProgress>[];
    for (final todo in _todosById.values) {
      if (todo.status == 'done' || todo.status == 'dismissed') {
        continue;
      }
      final items =
          _checklistItemsByTodoId[todo.id] ?? const <TodoChecklistItem>[];
      if (items.isEmpty) continue;
      var doneCount = 0;
      for (final item in items) {
        if (item.isDone) {
          doneCount += 1;
        }
      }
      progress.add(
        TodoChecklistProgress(
          todoId: todo.id,
          totalCount: items.length,
          doneCount: doneCount,
        ),
      );
    }
    return progress;
  }

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async {
    return _sortedSuggestions(_suggestionBucket(todoId));
  }

  @override
  Future<List<TodoChecklistSuggestion>> upsertGeneratedTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    if (!_todosById.containsKey(todoId)) {
      throw StateError('unknown_todo:$todoId');
    }
    final now = _touchNow();
    final bucket = _suggestionBucket(todoId);
    final blockedNorms = bucket
        .map((suggestion) =>
            _normalizeChecklistSuggestionContent(suggestion.content))
        .toSet();
    var nextSortOrder = bucket.isEmpty
        ? 0
        : bucket
                .map((suggestion) => suggestion.sortOrder)
                .reduce((left, right) => left > right ? left : right) +
            1;
    final generated = <TodoChecklistSuggestion>[];
    for (final rawSuggestion in suggestions) {
      final trimmed = rawSuggestion.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final normalized = _normalizeChecklistSuggestionContent(trimmed);
      if (normalized.isEmpty || !blockedNorms.add(normalized)) {
        continue;
      }
      final suggestion = TodoChecklistSuggestion(
        id: _nextId('suggestion'),
        todoId: todoId,
        content: trimmed,
        sortOrder: nextSortOrder,
        state: 'pending',
        source: source,
        generationKey: generationKey,
        createdAtMs: _asPlatformInt64(now),
        updatedAtMs: _asPlatformInt64(now),
        dismissedAtMs: null,
        appliedChecklistItemId: null,
      );
      bucket.add(suggestion);
      generated.add(suggestion);
      nextSortOrder += 1;
    }
    return generated;
  }

  @override
  Future<List<TodoChecklistItem>> applyTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    if (!_todosById.containsKey(todoId)) {
      throw StateError('unknown_todo:$todoId');
    }
    final bucket = _suggestionBucket(todoId);
    final checklist = _checklistBucket(todoId);
    final now = _touchNow();
    final created = <TodoChecklistItem>[];
    for (final suggestionId in suggestionIds) {
      final index = bucket.indexWhere((item) => item.id == suggestionId);
      if (index < 0) {
        throw StateError('unknown_checklist_suggestion:$suggestionId');
      }
      final suggestion = bucket[index];
      if (suggestion.state != 'pending') {
        continue;
      }
      final item = TodoChecklistItem(
        id: _nextId('checklist'),
        todoId: todoId,
        content: suggestion.content,
        sortOrder: checklist.length,
        isDone: false,
        createdAtMs: _asPlatformInt64(now),
        updatedAtMs: _asPlatformInt64(now),
      );
      checklist.add(item);
      created.add(item);
      bucket[index] = TodoChecklistSuggestion(
        id: suggestion.id,
        todoId: suggestion.todoId,
        content: suggestion.content,
        sortOrder: suggestion.sortOrder,
        state: 'applied',
        source: suggestion.source,
        generationKey: suggestion.generationKey,
        createdAtMs: suggestion.createdAtMs,
        updatedAtMs: _asPlatformInt64(now),
        dismissedAtMs: suggestion.dismissedAtMs,
        appliedChecklistItemId: item.id,
      );
    }
    return created;
  }

  @override
  Future<void> dismissTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final bucket = _suggestionBucket(todoId);
    final now = _touchNow();
    for (var i = 0; i < bucket.length; i += 1) {
      final suggestion = bucket[i];
      if (!suggestionIds.contains(suggestion.id) ||
          suggestion.state != 'pending') {
        continue;
      }
      bucket[i] = TodoChecklistSuggestion(
        id: suggestion.id,
        todoId: suggestion.todoId,
        content: suggestion.content,
        sortOrder: suggestion.sortOrder,
        state: 'dismissed',
        source: suggestion.source,
        generationKey: suggestion.generationKey,
        createdAtMs: suggestion.createdAtMs,
        updatedAtMs: _asPlatformInt64(now),
        dismissedAtMs: _asPlatformInt64(now),
        appliedChecklistItemId: suggestion.appliedChecklistItemId,
      );
    }
  }

  @override
  Future<void> dismissAllTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
  }) async {
    final ids = _suggestionBucket(todoId)
        .where((item) => item.state == 'pending')
        .map((item) => item.id)
        .toList(growable: false);
    await dismissTodoChecklistSuggestions(
      key,
      todoId: todoId,
      suggestionIds: ids,
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async {
    return _sortedActivities(
      _todoActivitiesById.values.where((activity) => activity.todoId == todoId),
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    return _sortedActivities(
      _todoActivitiesById.values.where(
        (activity) =>
            activity.createdAtMs >= startAtMsInclusive &&
            activity.createdAtMs < endAtMsExclusive,
      ),
    );
  }

  @override
  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) async {
    if (!_todoActivitiesById.containsKey(activityId)) {
      throw StateError('unknown_todo_activity:$activityId');
    }
    if (!_attachmentsBySha.containsKey(attachmentSha256)) {
      throw StateError('unknown_attachment:$attachmentSha256');
    }
    final bucket = _attachmentShasByTodoActivityId.putIfAbsent(
      activityId,
      () => <String>[],
    );
    if (!bucket.contains(attachmentSha256)) {
      bucket.add(attachmentSha256);
    }
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async {
    final shas =
        _attachmentShasByTodoActivityId[activityId] ?? const <String>[];
    return shas
        .map((sha) => _attachmentsBySha[sha])
        .whereType<Attachment>()
        .toList(growable: false);
  }
}
