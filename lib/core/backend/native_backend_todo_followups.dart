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

typedef DbUpsertTodoWithAutoFollowupJobFn = Future<Todo> Function({
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
  String? taskTypeHint,
  required PlatformInt64 nowMs,
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

typedef DbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimFn = Future<bool>
    Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required int jobStartedAtMs,
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
  required bool manualOverrideFollowup,
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

typedef DbListDueAutoTodoFollowupGenerationJobsFn
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

DbUpsertTodoWithAutoFollowupJobFn _resolveDbUpsertTodoWithAutoFollowupJob({
  DbUpsertTodoWithAutoFollowupJobFn? dbUpsertTodoWithAutoFollowupJob,
  DbUpsertTodoFn? dbUpsertTodo,
  DbEnqueueTodoFollowupGenerationJobFn? dbEnqueueTodoFollowupGenerationJob,
}) {
  final resolvedUpsertTodo = dbUpsertTodo ?? _dartDbUpsertTodo;
  final resolvedUpsertTodoWithAutoFollowupJob = dbUpsertTodoWithAutoFollowupJob;
  final resolvedEnqueueTodoFollowupGenerationJob =
      dbEnqueueTodoFollowupGenerationJob;
  return ({
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
    String? taskTypeHint,
    bool manualOverrideFollowup = false,
    required PlatformInt64 nowMs,
  }) async {
    final normalizedTaskTypeHint = taskTypeHint?.trim();
    final resolvedTaskType = resolveTodoFollowupTaskTypeForCreate(
      title: title,
      followupTaskTypeHint: normalizedTaskTypeHint,
    );
    if (!resolvedTaskType.allowsAutoFollowup) {
      return resolvedUpsertTodo(
        appDir: appDir,
        key: key,
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
      );
    }

    if (resolvedUpsertTodoWithAutoFollowupJob != null) {
      return resolvedUpsertTodoWithAutoFollowupJob(
        appDir: appDir,
        key: key,
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
        taskTypeHint:
            normalizedTaskTypeHint == null || normalizedTaskTypeHint.isEmpty
                ? null
                : normalizedTaskTypeHint,
        nowMs: nowMs,
      );
    }

    final todo = await resolvedUpsertTodo(
      appDir: appDir,
      key: key,
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    final wasCreated = todo.createdAtMs == todo.updatedAtMs;
    if (!wasCreated) {
      return todo;
    }
    if (resolvedEnqueueTodoFollowupGenerationJob == null) {
      return todo;
    }
    try {
      await resolvedEnqueueTodoFollowupGenerationJob(
        appDir: appDir,
        key: key,
        todoId: id,
        triggerKind: 'auto_create',
        manualOverrideFollowup: false,
        taskTypeHint:
            normalizedTaskTypeHint == null || normalizedTaskTypeHint.isEmpty
                ? null
                : normalizedTaskTypeHint,
        nowMs: nowMs,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'NativeAppBackend.upsertTodo auto follow-up '
        'enqueue failed for $id: $error',
      );
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'native_backend',
          context: ErrorDescription(
            'while enqueueing an automatic todo '
            'follow-up generation job',
          ),
        ),
      );
    }
    return todo;
  };
}
