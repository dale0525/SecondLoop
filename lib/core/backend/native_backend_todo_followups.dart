part of 'native_backend.dart';

typedef DbListTodosFn = Future<List<Todo>> Function({
  required String appDir,
  required List<int> key,
});

typedef DbGetTodoByIdFn = Future<Todo?> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbUpsertTodoFn = Future<Todo> Function({
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
});

typedef DbListTodoFollowupSuggestionsFn = Future<List<TodoFollowupSuggestion>>
    Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbUpsertGeneratedTodoFollowupSuggestionsFn
    = Future<List<TodoFollowupSuggestion>> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<TodoFollowupSuggestionDraftInput> suggestions,
  required String source,
  String? generationKey,
});

typedef DbApplyTodoFollowupSuggestionsFn = Future<List<TodoActivity>> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
});

typedef DbDismissTodoFollowupSuggestionsFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
});

typedef DbDismissAllTodoFollowupSuggestionsFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbEnqueueTodoFollowupGenerationJobFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String triggerKind,
  String? taskTypeHint,
  required PlatformInt64 nowMs,
});

typedef DbListDueTodoFollowupGenerationJobsFn
    = Future<List<TodoFollowupGenerationJob>> Function({
  required String appDir,
  required List<int> key,
  required PlatformInt64 nowMs,
  required int limit,
});

typedef DbGetTodoFollowupGenerationJobFn = Future<TodoFollowupGenerationJob?>
    Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbMarkTodoFollowupGenerationJobRunningFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
});

typedef DbMarkTodoFollowupGenerationJobFailedFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 attempts,
  required PlatformInt64 nextRetryAtMs,
  required String lastError,
  required PlatformInt64 nowMs,
});

typedef DbMarkTodoFollowupGenerationJobSucceededFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
});

typedef DbMarkTodoFollowupGenerationJobSkippedFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
});

typedef DbMarkTodoFollowupGenerationJobCanceledFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required PlatformInt64 nowMs,
});
