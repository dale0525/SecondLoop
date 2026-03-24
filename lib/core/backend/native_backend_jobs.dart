part of 'native_backend.dart';

mixin _NativeAppBackendJobs on _NativeAppBackendAccess {
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
