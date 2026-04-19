part of 'app_backend.dart';

String? normalizeTodoFollowupTaskTypeHint(String? followupTaskTypeHint) {
  final normalized = followupTaskTypeHint?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

TodoFollowupTaskType resolveTodoFollowupTaskTypeForCreate({
  required String title,
  String? followupTaskTypeHint,
}) {
  final hinted = TodoFollowupTaskType.fromWireValue(followupTaskTypeHint);
  if (hinted != TodoFollowupTaskType.unknown) {
    return hinted;
  }
  return classifyTodoFollowupTaskType(title);
}

Future<void> maybeEnqueueTodoFollowupGenerationOnCreate(
  AppBackend backend,
  Uint8List key, {
  required String todoId,
  required String title,
  String? followupTaskTypeHint,
}) async {
  if (!backend.supportsTodoFollowupSuggestions ||
      backend.autoEnqueuesTodoFollowupGenerationOnCreate) {
    return;
  }

  final taskTypeHint = normalizeTodoFollowupTaskTypeHint(followupTaskTypeHint);
  final taskType = resolveTodoFollowupTaskTypeForCreate(
    title: title,
    followupTaskTypeHint: taskTypeHint,
  );
  if (!taskType.allowsAutoFollowup) {
    return;
  }
  try {
    await backend.enqueueTodoFollowupGenerationJob(
      key,
      todoId: todoId,
      triggerKind: 'auto_create',
      taskTypeHint: taskTypeHint,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  } catch (error, stackTrace) {
    debugPrint(
      'AppBackend create follow-up enqueue failed for $todoId: $error',
    );
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app_backend',
        context: ErrorDescription(
          'while enqueueing an automatic todo follow-up generation job',
        ),
      ),
    );
  }
}

Future<Todo> createTodoWithFollowup(
  AppBackend backend,
  Uint8List key, {
  required String id,
  required String title,
  int? dueAtMs,
  required String status,
  String? sourceEntryId,
  int? reviewStage,
  int? nextReviewAtMs,
  int? lastReviewAtMs,
  String? followupTaskTypeHint,
}) async {
  final todo = await backend.upsertTodo(
    key,
    id: id,
    title: title,
    dueAtMs: dueAtMs,
    status: status,
    sourceEntryId: sourceEntryId,
    reviewStage: reviewStage,
    nextReviewAtMs: nextReviewAtMs,
    lastReviewAtMs: lastReviewAtMs,
  );

  await maybeEnqueueTodoFollowupGenerationOnCreate(
    backend,
    key,
    todoId: id,
    title: title,
    followupTaskTypeHint: followupTaskTypeHint,
  );
  return todo;
}

extension AppBackendTodoFollowups on AppBackend {
  Future<List<TodoFollowupSuggestion>>
      upsertGeneratedTodoFollowupSuggestionDraft(
    Uint8List key, {
    required String todoId,
    required TodoFollowupSuggestionDraftInput suggestion,
    required String source,
    String? generationKey,
  }) {
    return upsertGeneratedTodoFollowupSuggestions(
      key,
      todoId: todoId,
      suggestions: <TodoFollowupSuggestionDraftInput>[suggestion],
      source: source,
      generationKey: generationKey,
    );
  }
}
