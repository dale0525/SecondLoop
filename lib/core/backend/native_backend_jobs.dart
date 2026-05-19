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
    throw _retiredNativeRuntimeFeature('dbEnqueueSemanticParseJob');
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    throw _retiredNativeRuntimeFeature('dbListDueSemanticParseJobs');
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    throw _retiredNativeRuntimeFeature('dbListSemanticParseJobsByMessageIds');
  }

  @override
  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobRunning');
  }

  @override
  Future<int?> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbClaimSemanticParseJobRunning');
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
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobFailed');
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
    throw _retiredNativeRuntimeFeature(
      'dbMarkSemanticParseJobFailedIfCurrentAttempt',
    );
  }

  @override
  Future<void> markSemanticParseJobRetry(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobRetry');
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
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobSucceeded');
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
    throw _retiredNativeRuntimeFeature(
      'dbMarkSemanticParseJobSucceededIfCurrentAttempt',
    );
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobCanceled');
  }

  @override
  Future<int> requeueRunningSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbRequeueRunningSemanticParseJobs');
  }

  @override
  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'dbMarkSemanticParseJobCanceledIfCurrentAttempt',
    );
  }

  @override
  Future<List<String>?> completeSemanticParseNoActionIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'dbCompleteSemanticParseNoActionIfCurrentAttempt',
    );
  }

  @override
  Future<bool> completeSemanticParseCreateIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    required String status,
    int? dueAtMs,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
    required List<String> checklistSuggestions,
    required String checklistSource,
    String? checklistGenerationKey,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'dbCompleteSemanticParseCreateIfCurrentAttempt',
    );
  }

  @override
  Future<bool> completeSemanticParseFollowupIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    String? todoTitle,
    String? newStatus,
    int? dueAtMs,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'dbCompleteSemanticParseFollowupIfCurrentAttempt',
    );
  }

  @override
  Future<bool> completeSemanticParseTodoCommandIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required SecretaryTodoCommand command,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'dbCompleteSemanticParseTodoCommandIfCurrentAttempt',
    );
  }

  @override
  Future<List<String>> applySemanticParseTagsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required List<String> suggestedTags,
  }) async {
    throw _retiredNativeRuntimeFeature(
        'dbApplySemanticParseTagsIfCurrentAttempt');
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
    throw _retiredNativeRuntimeFeature(
      'dbUpsertTodoFromSemanticParseIfCurrentAttempt',
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
    throw _retiredNativeRuntimeFeature(
      'dbUpsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt',
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
    throw _retiredNativeRuntimeFeature(
      'dbSetTodoStatusFromSemanticParseIfCurrentAttempt',
    );
  }

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkSemanticParseJobUndone');
  }
}
