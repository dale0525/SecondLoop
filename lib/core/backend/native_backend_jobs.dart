part of 'native_backend.dart';

mixin _NativeAppBackendJobs on _NativeAppBackendAccess
    implements SemanticParseAttemptAwareBackend {
  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    bool manualOverrideFollowup = false,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbEnqueueTodoFollowupGenerationJob(
      appDir: appDir,
      key: key,
      todoId: todoId,
      triggerKind: triggerKind,
      manualOverrideFollowup: manualOverrideFollowup,
      taskTypeHint: taskTypeHint,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return _dbListDueTodoFollowupGenerationJobs(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  Future<List<TodoFollowupGenerationJob>> listDueAutoTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 1,
  }) async {
    final appDir = await _getAppDir();
    return _dbListDueAutoTodoFollowupGenerationJobs(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<TodoFollowupGenerationJob?> getTodoFollowupGenerationJob(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbGetTodoFollowupGenerationJob(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<void> markTodoFollowupGenerationJobRunning(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbMarkTodoFollowupGenerationJobRunning(
      appDir: appDir,
      key: key,
      todoId: todoId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markTodoFollowupGenerationJobFailed(
    Uint8List key, {
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbMarkTodoFollowupGenerationJobFailed(
      appDir: appDir,
      key: key,
      todoId: todoId,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markTodoFollowupGenerationJobSucceeded(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbMarkTodoFollowupGenerationJobSucceeded(
      appDir: appDir,
      key: key,
      todoId: todoId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markTodoFollowupGenerationJobSkipped(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbMarkTodoFollowupGenerationJobSkipped(
      appDir: appDir,
      key: key,
      todoId: todoId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markTodoFollowupGenerationJobCanceled(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await _dbMarkTodoFollowupGenerationJobCanceled(
      appDir: appDir,
      key: key,
      todoId: todoId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueSemanticParseJob(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueSemanticParseJobs(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListSemanticParseJobsByMessageIds(
      appDir: appDir,
      key: key,
      messageIds: messageIds,
    );
  }

  @override
  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobRunning(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<int> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    final attemptId = await rust_core.dbClaimSemanticParseJobRunning(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
    return attemptId.toInt();
  }

  @override
  Future<void> markSemanticParseJobFailed(
    Uint8List key, {
    required String messageId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobFailed(
      appDir: appDir,
      key: key,
      messageId: messageId,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<bool> markSemanticParseJobFailedIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbMarkSemanticParseJobFailedIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobRetry(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobRetry(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobSucceeded(
      appDir: appDir,
      key: key,
      messageId: messageId,
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<bool> markSemanticParseJobSucceededIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbMarkSemanticParseJobSucceededIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobCanceled(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbMarkSemanticParseJobCanceledIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<String>> applySemanticParseTagsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required List<String> suggestedTags,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbApplySemanticParseTagsIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      suggestedTags: suggestedTags,
    );
  }

  @override
  Future<String?> upsertTodoFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    int? dueAtMs,
    required String status,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    String? taskTypeHint,
    String? recurrenceRuleJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbUpsertTodoFromSemanticParseIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      todoId: todoId,
      title: title,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      status: status,
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
      taskTypeHint: taskTypeHint,
      recurrenceRuleJson: recurrenceRuleJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> upsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      todoId: todoId,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }

  @override
  Future<String?> setTodoStatusFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String newStatus,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetTodoStatusFromSemanticParseIfCurrentAttempt(
      appDir: appDir,
      key: key,
      messageId: messageId,
      expectedAttemptId: PlatformInt64Util.from(expectedAttemptId),
      todoId: todoId,
      newStatus: newStatus,
    );
  }

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobUndone(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }
}
