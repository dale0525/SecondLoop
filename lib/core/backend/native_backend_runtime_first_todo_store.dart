part of 'native_backend.dart';

Future<Todo> _dartDbUpsertTodo({
  required String appDir,
  required List<int> key,
  required String id,
  required String title,
  PlatformInt64? dueAtMs,
  required String status,
  String? sourceEntryId,
  PlatformInt64? reviewStage,
  PlatformInt64? nextReviewAtMs,
  PlatformInt64? lastReviewAtMs,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  final existing = state.todos[id];
  final todo = Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs,
    status: status,
    sourceEntryId: sourceEntryId,
    createdAtMs: existing?.createdAtMs ?? now,
    updatedAtMs: now,
    reviewStage: reviewStage,
    nextReviewAtMs: nextReviewAtMs,
    lastReviewAtMs: lastReviewAtMs,
    manualImportanceNudgeScore: existing?.manualImportanceNudgeScore,
    manualUrgencyNudgeScore: existing?.manualUrgencyNudgeScore,
  );
  state.todos[id] = todo;
  return todo;
}

Future<List<Todo>> _dartDbListTodos({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.todos.values.toList(growable: false)
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

Future<Todo?> _dartDbGetTodoById({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.todos[todoId];
}

Future<List<Todo>> _dartDbListTodosCreatedInRange({
  required String appDir,
  required List<int> key,
  required PlatformInt64 startAtMsInclusive,
  required PlatformInt64 endAtMsExclusive,
}) async {
  final todos = await _dartDbListTodos(appDir: appDir, key: key);
  return todos
      .where((todo) =>
          todo.createdAtMs >= startAtMsInclusive &&
          todo.createdAtMs < endAtMsExclusive)
      .toList(growable: false);
}

Future<Todo> _dartDbSetTodoStatus({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String newStatus,
  String? sourceMessageId,
}) {
  return _dartDbTransitionTodo(
    appDir: appDir,
    key: key,
    todoId: todoId,
    newStatus: newStatus,
    clearDueAtMs: false,
    clearReviewStage: false,
    clearNextReviewAtMs: false,
    clearLastReviewAtMs: false,
    clearManualImportanceNudgeScore: false,
    clearManualUrgencyNudgeScore: false,
    sourceMessageId: sourceMessageId,
  );
}

Future<Todo> _dartDbUpdateTodoStatusWithScope({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String newStatus,
  String? sourceMessageId,
  required String scope,
}) {
  return _dartDbSetTodoStatus(
    appDir: appDir,
    key: key,
    todoId: todoId,
    newStatus: newStatus,
    sourceMessageId: sourceMessageId,
  );
}

Future<Todo> _dartDbUpdateTodoDueWithScope({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 dueAtMs,
  required String scope,
}) {
  return _dartDbTransitionTodo(
    appDir: appDir,
    key: key,
    todoId: todoId,
    dueAtMs: dueAtMs,
    clearDueAtMs: false,
    clearReviewStage: false,
    clearNextReviewAtMs: false,
    clearLastReviewAtMs: false,
    clearManualImportanceNudgeScore: false,
    clearManualUrgencyNudgeScore: false,
  );
}

Future<void> _dartDbUpsertTodoRecurrence({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String seriesId,
  required String ruleJson,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.todos.containsKey(todoId)) {
    throw StateError('todo_not_found:$todoId');
  }
  state.todoRecurrenceRules[todoId] = ruleJson;
}

Future<String?> _dartDbGetTodoRecurrenceRuleJson({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.todoRecurrenceRules[todoId];
}

Future<void> _dartDbUpdateTodoRecurrenceRuleWithScope({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String ruleJson,
  required String scope,
}) async {
  await _dartDbUpsertTodoRecurrence(
    appDir: appDir,
    key: key,
    todoId: todoId,
    seriesId: '',
    ruleJson: ruleJson,
  );
}

Future<void> _dartDbDeleteTodoAndAssociatedMessages({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.todos.remove(todoId);
  state.todoRecurrenceRules.remove(todoId);
  state.checklistItems.removeWhere((_, item) => item.todoId == todoId);
  state.checklistSuggestions
      .removeWhere((_, suggestion) => suggestion.todoId == todoId);
  state.todoFollowupSuggestions
      .removeWhere((_, suggestion) => suggestion.todoId == todoId);
  final removedActivityIds = state.todoActivities.values
      .where((activity) => activity.todoId == todoId)
      .map((activity) => activity.id)
      .toList(growable: false);
  state.todoActivities.removeWhere((_, activity) => activity.todoId == todoId);
  for (final activityId in removedActivityIds) {
    state.todoActivityAttachmentShas.remove(activityId);
  }
}

Future<TodoActivity> _dartDbAppendTodoNote({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String content,
  String? sourceMessageId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.todos.containsKey(todoId)) {
    throw StateError('todo_not_found:$todoId');
  }
  final activity = TodoActivity(
    id: 'todo_activity_${state.nextTodoActivitySeq++}',
    todoId: todoId,
    activityType: 'note',
    content: content,
    sourceMessageId: sourceMessageId,
    createdAtMs: _dartRuntimeNowMs(),
  );
  state.todoActivities[activity.id] = activity;
  return activity;
}

Future<TodoActivity> _dartDbMoveTodoActivity({
  required String appDir,
  required List<int> key,
  required String activityId,
  required String toTodoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.todos.containsKey(toTodoId)) {
    throw StateError('todo_not_found:$toTodoId');
  }
  final existing = state.todoActivities[activityId];
  if (existing == null) {
    throw StateError('todo_activity_not_found:$activityId');
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
  state.todoActivities[activityId] = moved;
  return moved;
}

Future<List<TodoActivity>> _dartDbListTodoActivities({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final activities = state.todoActivities.values
      .where((activity) => activity.todoId == todoId)
      .toList(growable: false);
  activities.sort((a, b) {
    final byTime = a.createdAtMs.compareTo(b.createdAtMs);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return activities;
}

Future<List<TodoActivity>> _dartDbListTodoActivitiesInRange({
  required String appDir,
  required List<int> key,
  required PlatformInt64 startAtMsInclusive,
  required PlatformInt64 endAtMsExclusive,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final activities = state.todoActivities.values
      .where((activity) =>
          activity.createdAtMs >= startAtMsInclusive &&
          activity.createdAtMs < endAtMsExclusive)
      .toList(growable: false);
  activities.sort((a, b) {
    final byTime = a.createdAtMs.compareTo(b.createdAtMs);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return activities;
}

Future<void> _dartDbLinkAttachmentToTodoActivity({
  required String appDir,
  required List<int> key,
  required String activityId,
  required String attachmentSha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.todoActivities.containsKey(activityId)) {
    throw StateError('todo_activity_not_found:$activityId');
  }
  final attachments = state.todoActivityAttachmentShas
      .putIfAbsent(activityId, () => <String>[]);
  if (!attachments.contains(attachmentSha256)) {
    attachments.add(attachmentSha256);
  }
}

Future<List<Attachment>> _dartDbListTodoActivityAttachments({
  required String appDir,
  required List<int> key,
  required String activityId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  return (state.todoActivityAttachmentShas[activityId] ?? const <String>[])
      .map(
        (sha) => Attachment(
          sha256: sha,
          mimeType: 'application/octet-stream',
          path: '',
          byteLen: PlatformInt64Util.from(0),
          createdAtMs: now,
        ),
      )
      .toList(growable: false);
}

Future<Todo> _dartDbTransitionTodo({
  required String appDir,
  required List<int> key,
  required String todoId,
  String? newStatus,
  PlatformInt64? dueAtMs,
  required bool clearDueAtMs,
  PlatformInt64? reviewStage,
  required bool clearReviewStage,
  PlatformInt64? nextReviewAtMs,
  required bool clearNextReviewAtMs,
  PlatformInt64? lastReviewAtMs,
  required bool clearLastReviewAtMs,
  PlatformInt64? manualImportanceNudgeScore,
  required bool clearManualImportanceNudgeScore,
  PlatformInt64? manualUrgencyNudgeScore,
  required bool clearManualUrgencyNudgeScore,
  String? sourceMessageId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final existing = state.todos[todoId];
  if (existing == null) {
    throw StateError('todo_not_found:$todoId');
  }
  final now = _dartRuntimeNowMs();
  final todo = Todo(
    id: existing.id,
    title: existing.title,
    dueAtMs: clearDueAtMs ? null : (dueAtMs ?? existing.dueAtMs),
    status: newStatus ?? existing.status,
    sourceEntryId: existing.sourceEntryId,
    createdAtMs: existing.createdAtMs,
    updatedAtMs: now,
    reviewStage:
        clearReviewStage ? null : (reviewStage ?? existing.reviewStage),
    nextReviewAtMs: clearNextReviewAtMs
        ? null
        : (nextReviewAtMs ?? existing.nextReviewAtMs),
    lastReviewAtMs: clearLastReviewAtMs
        ? null
        : (lastReviewAtMs ?? existing.lastReviewAtMs),
    manualImportanceNudgeScore: clearManualImportanceNudgeScore
        ? null
        : (manualImportanceNudgeScore ?? existing.manualImportanceNudgeScore),
    manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
        ? null
        : (manualUrgencyNudgeScore ?? existing.manualUrgencyNudgeScore),
  );
  state.todos[todoId] = todo;
  return todo;
}

Future<TodoChecklistItem> _dartDbCreateTodoChecklistItem({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String content,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  final item = TodoChecklistItem(
    id: 'checklist_item_${state.nextChecklistItemSeq++}',
    todoId: todoId,
    content: content,
    isDone: false,
    sortOrder: _nextChecklistSortOrder(state, todoId),
    createdAtMs: now,
    updatedAtMs: now,
  );
  state.checklistItems[item.id] = item;
  return item;
}

Future<List<TodoChecklistItem>> _dartDbListTodoChecklistItems({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return _sortedChecklistItems(state, todoId);
}

Future<TodoChecklistItem> _dartDbUpdateTodoChecklistItemContent({
  required String appDir,
  required List<int> key,
  required String itemId,
  required String content,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final item = state.checklistItems[itemId];
  if (item == null) throw StateError('todo_checklist_item_not_found:$itemId');
  final updated = _copyDartChecklistItem(
    item,
    content: content,
    updatedAtMs: _dartRuntimeNowMs(),
  );
  state.checklistItems[itemId] = updated;
  return updated;
}

Future<TodoChecklistItem> _dartDbSetTodoChecklistItemDone({
  required String appDir,
  required List<int> key,
  required String itemId,
  required bool isDone,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final item = state.checklistItems[itemId];
  if (item == null) throw StateError('todo_checklist_item_not_found:$itemId');
  final updated = _copyDartChecklistItem(
    item,
    isDone: isDone,
    updatedAtMs: _dartRuntimeNowMs(),
  );
  state.checklistItems[itemId] = updated;
  return updated;
}

Future<void> _dartDbDeleteTodoChecklistItem({
  required String appDir,
  required List<int> key,
  required String itemId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.checklistItems.remove(itemId);
}

Future<void> _dartDbReorderTodoChecklistItems({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> orderedItemIds,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (var index = 0; index < orderedItemIds.length; index += 1) {
    final itemId = orderedItemIds[index];
    final item = state.checklistItems[itemId];
    if (item == null || item.todoId != todoId) continue;
    state.checklistItems[itemId] = _copyDartChecklistItem(
      item,
      sortOrder: index,
      updatedAtMs: now,
    );
  }
}

Future<List<TodoChecklistProgress>> _dartDbListTodoChecklistProgress({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final todoIds = <String>{...state.todos.keys};
  for (final item in state.checklistItems.values) {
    todoIds.add(item.todoId);
  }
  final progress = <TodoChecklistProgress>[];
  for (final todoId in todoIds) {
    final items = _sortedChecklistItems(state, todoId);
    if (items.isEmpty) continue;
    progress.add(
      TodoChecklistProgress(
        todoId: todoId,
        doneCount: items.where((item) => item.isDone).length,
        totalCount: items.length,
      ),
    );
  }
  progress.sort((a, b) => a.todoId.compareTo(b.todoId));
  return progress;
}

Future<List<TodoChecklistSuggestion>> _dartDbListTodoChecklistSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return _sortedChecklistSuggestions(state, todoId);
}

Future<List<TodoChecklistSuggestion>>
    _dartDbUpsertGeneratedTodoChecklistSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestions,
  required String source,
  String? generationKey,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final content in suggestions) {
    final suggestion = TodoChecklistSuggestion(
      id: 'checklist_suggestion_${state.nextChecklistSuggestionSeq++}',
      todoId: todoId,
      content: content,
      sortOrder: _nextChecklistSuggestionSortOrder(state, todoId),
      state: 'pending',
      source: source,
      generationKey: generationKey,
      createdAtMs: now,
      updatedAtMs: now,
      dismissedAtMs: null,
      appliedChecklistItemId: null,
    );
    state.checklistSuggestions[suggestion.id] = suggestion;
  }
  return _sortedChecklistSuggestions(state, todoId);
}

Future<List<TodoChecklistItem>> _dartDbApplyTodoChecklistSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  final appliedItems = <TodoChecklistItem>[];
  for (final suggestionId in suggestionIds) {
    final suggestion = state.checklistSuggestions[suggestionId];
    if (suggestion == null ||
        suggestion.todoId != todoId ||
        suggestion.state != 'pending') {
      continue;
    }
    final item = TodoChecklistItem(
      id: 'checklist_item_${state.nextChecklistItemSeq++}',
      todoId: todoId,
      content: suggestion.content,
      isDone: false,
      sortOrder: _nextChecklistSortOrder(state, todoId),
      createdAtMs: now,
      updatedAtMs: now,
    );
    state.checklistItems[item.id] = item;
    state.checklistSuggestions[suggestionId] = _copyDartChecklistSuggestion(
      suggestion,
      state: 'applied',
      appliedChecklistItemId: item.id,
      updatedAtMs: now,
    );
    appliedItems.add(item);
  }
  return appliedItems;
}

Future<void> _dartDbDismissTodoChecklistSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final suggestionId in suggestionIds) {
    final suggestion = state.checklistSuggestions[suggestionId];
    if (suggestion == null || suggestion.todoId != todoId) continue;
    state.checklistSuggestions[suggestionId] = _copyDartChecklistSuggestion(
      suggestion,
      state: 'dismissed',
      dismissedAtMs: now,
      updatedAtMs: now,
    );
  }
}

Future<void> _dartDbDismissAllTodoChecklistSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final suggestion in _sortedChecklistSuggestions(state, todoId)) {
    if (suggestion.state != 'pending') continue;
    state.checklistSuggestions[suggestion.id] = _copyDartChecklistSuggestion(
      suggestion,
      state: 'dismissed',
      dismissedAtMs: now,
      updatedAtMs: now,
    );
  }
}

PlatformInt64 _nextChecklistSortOrder(
  _DartNativeRuntimeState state,
  String todoId,
) {
  final items = _sortedChecklistItems(state, todoId);
  if (items.isEmpty) return 0;
  return items.last.sortOrder + 1;
}

PlatformInt64 _nextChecklistSuggestionSortOrder(
  _DartNativeRuntimeState state,
  String todoId,
) {
  final suggestions = _sortedChecklistSuggestions(state, todoId);
  if (suggestions.isEmpty) return 0;
  return suggestions.last.sortOrder + 1;
}

List<TodoChecklistItem> _sortedChecklistItems(
  _DartNativeRuntimeState state,
  String todoId,
) {
  final items = state.checklistItems.values
      .where((item) => item.todoId == todoId)
      .toList(growable: false);
  items.sort((a, b) {
    final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
    return bySortOrder != 0 ? bySortOrder : a.id.compareTo(b.id);
  });
  return items;
}

List<TodoChecklistSuggestion> _sortedChecklistSuggestions(
  _DartNativeRuntimeState state,
  String todoId,
) {
  final suggestions = state.checklistSuggestions.values
      .where((suggestion) => suggestion.todoId == todoId)
      .toList(growable: false);
  suggestions.sort((a, b) {
    final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
    return bySortOrder != 0 ? bySortOrder : a.id.compareTo(b.id);
  });
  return suggestions;
}

TodoChecklistItem _copyDartChecklistItem(
  TodoChecklistItem item, {
  String? content,
  bool? isDone,
  PlatformInt64? sortOrder,
  PlatformInt64? updatedAtMs,
}) {
  return TodoChecklistItem(
    id: item.id,
    todoId: item.todoId,
    content: content ?? item.content,
    isDone: isDone ?? item.isDone,
    sortOrder: sortOrder ?? item.sortOrder,
    createdAtMs: item.createdAtMs,
    updatedAtMs: updatedAtMs ?? item.updatedAtMs,
  );
}

TodoChecklistSuggestion _copyDartChecklistSuggestion(
  TodoChecklistSuggestion suggestion, {
  String? state,
  PlatformInt64? dismissedAtMs,
  String? appliedChecklistItemId,
  PlatformInt64? updatedAtMs,
}) {
  return TodoChecklistSuggestion(
    id: suggestion.id,
    todoId: suggestion.todoId,
    content: suggestion.content,
    sortOrder: suggestion.sortOrder,
    state: state ?? suggestion.state,
    source: suggestion.source,
    generationKey: suggestion.generationKey,
    createdAtMs: suggestion.createdAtMs,
    updatedAtMs: updatedAtMs ?? suggestion.updatedAtMs,
    dismissedAtMs: dismissedAtMs ?? suggestion.dismissedAtMs,
    appliedChecklistItemId:
        appliedChecklistItemId ?? suggestion.appliedChecklistItemId,
  );
}

Future<void> _dartDbEnqueueTodoFollowupGenerationJob({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String triggerKind,
  required bool manualOverrideFollowup,
  String? taskTypeHint,
  required PlatformInt64 nowMs,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final existing = state.todoFollowupJobs[todoId];
  state.todoFollowupJobs[todoId] = TodoFollowupGenerationJob(
    todoId: todoId,
    triggerKind: triggerKind,
    status: 'pending',
    attempts: existing?.attempts ?? 0,
    nextRetryAtMs: null,
    lastError: null,
    includeManualFollowups:
        manualOverrideFollowup || triggerKind != 'auto_create',
    manualOverrideFollowup: manualOverrideFollowup,
    taskTypeHint: taskTypeHint,
    createdAtMs: existing?.createdAtMs ?? nowMs,
    updatedAtMs: nowMs,
  );
}

Future<List<TodoFollowupGenerationJob>>
    _dartDbListDueTodoFollowupGenerationJobs({
  required String appDir,
  required List<int> key,
  required PlatformInt64 nowMs,
  required int limit,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final jobs = state.todoFollowupJobs.values
      .where((job) => _dartTodoFollowupJobIsDue(job, nowMs))
      .toList(growable: false);
  jobs.sort((a, b) {
    final byNextRetry = compareNullablePlatformIntAsc(
      a.nextRetryAtMs,
      b.nextRetryAtMs,
      nullsLast: false,
    );
    if (byNextRetry != 0) return byNextRetry;
    return a.updatedAtMs.compareTo(b.updatedAtMs);
  });
  return jobs.take(limit).toList(growable: false);
}

Future<List<TodoFollowupGenerationJob>>
    _dartDbListDueAutoTodoFollowupGenerationJobs({
  required String appDir,
  required List<int> key,
  required PlatformInt64 nowMs,
  required int limit,
}) async {
  final jobs = await _dartDbListDueTodoFollowupGenerationJobs(
    appDir: appDir,
    key: key,
    nowMs: nowMs,
    limit: limit,
  );
  return jobs
      .where((job) => job.triggerKind == 'auto_create')
      .take(limit)
      .toList(growable: false);
}

Future<TodoFollowupGenerationJob?> _dartDbGetTodoFollowupGenerationJob({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.todoFollowupJobs[todoId];
}

bool _dartTodoFollowupJobIsDue(
  TodoFollowupGenerationJob job,
  PlatformInt64 nowMs,
) {
  if (job.status != 'pending' && job.status != 'failed') return false;
  final nextRetryAtMs = job.nextRetryAtMs;
  return nextRetryAtMs == null || nextRetryAtMs <= nowMs;
}

TodoFollowupGenerationJob _copyDartTodoFollowupJob(
  TodoFollowupGenerationJob job, {
  required String status,
  PlatformInt64? attempts,
  PlatformInt64? nextRetryAtMs,
  String? lastError,
  required PlatformInt64 nowMs,
}) {
  return TodoFollowupGenerationJob(
    todoId: job.todoId,
    triggerKind: job.triggerKind,
    status: status,
    attempts: attempts ?? job.attempts,
    nextRetryAtMs: nextRetryAtMs,
    lastError: lastError,
    includeManualFollowups: job.includeManualFollowups,
    manualOverrideFollowup: job.manualOverrideFollowup,
    taskTypeHint: job.taskTypeHint,
    createdAtMs: job.createdAtMs,
    updatedAtMs: nowMs,
  );
}

Future<void> _dartUpdateTodoFollowupGenerationJob({
  required String appDir,
  required List<int> key,
  required String todoId,
  required TodoFollowupGenerationJob Function(TodoFollowupGenerationJob job)
      update,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final existing = state.todoFollowupJobs[todoId];
  if (existing == null) return;
  state.todoFollowupJobs[todoId] = update(existing);
}

Future<void> _dartDbMarkTodoFollowupGenerationJobRunning({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
}) {
  return _dartUpdateTodoFollowupGenerationJob(
    appDir: appDir,
    key: key,
    todoId: todoId,
    update: (job) => _copyDartTodoFollowupJob(
      job,
      status: 'running',
      nextRetryAtMs: job.nextRetryAtMs,
      lastError: job.lastError,
      nowMs: nowMs,
    ),
  );
}

Future<void> _dartDbMarkTodoFollowupGenerationJobFailed({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 attempts,
  required PlatformInt64 nextRetryAtMs,
  required String lastError,
  required PlatformInt64 nowMs,
}) {
  return _dartUpdateTodoFollowupGenerationJob(
    appDir: appDir,
    key: key,
    todoId: todoId,
    update: (job) => _copyDartTodoFollowupJob(
      job,
      status: 'failed',
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    ),
  );
}

Future<void> _dartDbMarkTodoFollowupGenerationJobSucceeded({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
}) {
  return _dartUpdateTodoFollowupGenerationJob(
    appDir: appDir,
    key: key,
    todoId: todoId,
    update: (job) => _copyDartTodoFollowupJob(
      job,
      status: 'succeeded',
      nowMs: nowMs,
    ),
  );
}

Future<void> _dartDbMarkTodoFollowupGenerationJobSkipped({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
}) {
  return _dartUpdateTodoFollowupGenerationJob(
    appDir: appDir,
    key: key,
    todoId: todoId,
    update: (job) => _copyDartTodoFollowupJob(
      job,
      status: 'skipped',
      nowMs: nowMs,
    ),
  );
}

Future<void> _dartDbMarkTodoFollowupGenerationJobCanceled({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
}) {
  return _dartUpdateTodoFollowupGenerationJob(
    appDir: appDir,
    key: key,
    todoId: todoId,
    update: (job) => _copyDartTodoFollowupJob(
      job,
      status: 'canceled',
      nowMs: nowMs,
    ),
  );
}
