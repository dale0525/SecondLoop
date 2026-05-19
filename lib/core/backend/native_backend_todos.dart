part of 'native_backend.dart';

abstract class _NativeAppBackendAccess
    implements
        AppBackend,
        AttachmentsBackend,
        AttachmentAnnotationMutationsBackend,
        AssistantCitationWriteBackend,
        DetachedAskCompletionRecoveryBackend,
        SecretaryBackend {
  Future<String> _getAppDir();

  SecureBlobStore get _secureBlobStore;

  DbListTodosFn get _dbListTodos;
  DbGetTodoByIdFn get _dbGetTodoById;
  DbUpsertTodoWithAutoFollowupJobFn get _dbUpsertTodoWithAutoFollowupJob;
  DbInsertAttachmentFn get _dbInsertAttachment;
  DbProcessPendingMessageEmbeddingsFn get _dbProcessPendingMessageEmbeddings;
  DbReleaseLocalEmbeddingModelIfIdleFn get _dbReleaseLocalEmbeddingModelIfIdle;
  AskAiStreamScopedFn get _askAiStreamScoped;
  AskAiStreamCloudGatewayScopedFn get _askAiStreamCloudGatewayScoped;
  DbCreateTodoChecklistItemFn get _dbCreateTodoChecklistItem;
  DbListTodoChecklistItemsFn get _dbListTodoChecklistItems;
  DbUpdateTodoChecklistItemContentFn get _dbUpdateTodoChecklistItemContent;
  DbSetTodoChecklistItemDoneFn get _dbSetTodoChecklistItemDone;
  DbDeleteTodoChecklistItemFn get _dbDeleteTodoChecklistItem;
  DbReorderTodoChecklistItemsFn get _dbReorderTodoChecklistItems;
  DbListTodoChecklistProgressFn get _dbListTodoChecklistProgress;
  DbListTodoChecklistSuggestionsFn get _dbListTodoChecklistSuggestions;
  DbUpsertGeneratedTodoChecklistSuggestionsFn
      get _dbUpsertGeneratedTodoChecklistSuggestions;
  DbApplyTodoChecklistSuggestionsFn get _dbApplyTodoChecklistSuggestions;
  DbDismissTodoChecklistSuggestionsFn get _dbDismissTodoChecklistSuggestions;
  DbDismissAllTodoChecklistSuggestionsFn
      get _dbDismissAllTodoChecklistSuggestions;
  DbListTodoFollowupSuggestionsFn get _dbListTodoFollowupSuggestions;
  DbUpsertGeneratedTodoFollowupSuggestionsFn
      get _dbUpsertGeneratedTodoFollowupSuggestions;
  DbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimFn
      get _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim;
  DbApplyTodoFollowupSuggestionsFn get _dbApplyTodoFollowupSuggestions;
  DbDismissTodoFollowupSuggestionsFn get _dbDismissTodoFollowupSuggestions;
  DbDismissAllTodoFollowupSuggestionsFn
      get _dbDismissAllTodoFollowupSuggestions;
  DbEnqueueTodoFollowupGenerationJobFn get _dbEnqueueTodoFollowupGenerationJob;
  DbListDueTodoFollowupGenerationJobsFn
      get _dbListDueTodoFollowupGenerationJobs;
  DbListDueAutoTodoFollowupGenerationJobsFn
      get _dbListDueAutoTodoFollowupGenerationJobs;
  DbGetTodoFollowupGenerationJobFn get _dbGetTodoFollowupGenerationJob;
  DbMarkTodoFollowupGenerationJobRunningFn
      get _dbMarkTodoFollowupGenerationJobRunning;
  DbMarkTodoFollowupGenerationJobFailedFn
      get _dbMarkTodoFollowupGenerationJobFailed;
  DbMarkTodoFollowupGenerationJobSucceededFn
      get _dbMarkTodoFollowupGenerationJobSucceeded;
  DbMarkTodoFollowupGenerationJobSkippedFn
      get _dbMarkTodoFollowupGenerationJobSkipped;
  DbMarkTodoFollowupGenerationJobCanceledFn
      get _dbMarkTodoFollowupGenerationJobCanceled;
  DbCreateSecretaryMemoryProposalFn? get _dbCreateSecretaryMemoryProposal;
  DbListSecretaryMemoryProposalsFn? get _dbListSecretaryMemoryProposals;
  DbAcceptSecretaryMemoryProposalFn? get _dbAcceptSecretaryMemoryProposal;
  DbDismissSecretaryMemoryProposalFn? get _dbDismissSecretaryMemoryProposal;
  DbListMemoryPagesFn? get _dbListMemoryPages;
  DbGetMemoryPageFn? get _dbGetMemoryPage;
  DbCorrectMemoryPageFn? get _dbCorrectMemoryPage;
  DbSetMemoryPageStateFn? get _dbArchiveMemoryPage;
  DbSetMemoryPageStateFn? get _dbRestoreMemoryPage;
  DbUpsertPlanningOutputFn get _dbUpsertPlanningOutput;
  DbListPlanningOutputsFn get _dbListPlanningOutputs;
  DbCreateSecretaryRunFn get _dbCreateSecretaryRun;
  DbCreateSecretaryToolCallFn get _dbCreateSecretaryToolCall;
  DbListSecretaryToolCallsForRunFn get _dbListSecretaryToolCallsForRun;
}

mixin _NativeAppBackendTodos on _NativeAppBackendAccess {
  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dbListTodos(appDir: appDir, key: key);
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    final appDir = await _getAppDir();
    return _dbGetTodoById(appDir: appDir, key: key, todoId: todoId);
  }

  @override
  Future<List<Todo>> listTodosCreatedInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbListTodosCreatedInRange(
      appDir: appDir,
      key: key,
      startAtMsInclusive: PlatformInt64Util.from(startAtMsInclusive),
      endAtMsExclusive: PlatformInt64Util.from(endAtMsExclusive),
    );
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
  }) {
    return _upsertTodoInternal(
      key,
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
    );
  }

  @override
  Future<Todo> upsertTodoFromSemanticCreate(
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
  }) {
    return _upsertTodoInternal(
      key,
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      followupTaskTypeHint: followupTaskTypeHint,
    );
  }

  Future<Todo> _upsertTodoInternal(
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
    String? followupTaskTypeHint,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertTodoWithAutoFollowupJob(
      appDir: appDir,
      key: key,
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
      taskTypeHint: followupTaskTypeHint,
      nowMs: PlatformInt64Util.from(DateTime.now().millisecondsSinceEpoch),
    );
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSetTodoStatus(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
    );
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
    final appDir = await _getAppDir();
    return _dartDbTransitionTodo(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      clearDueAtMs: clearDueAtMs,
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      clearReviewStage: clearReviewStage,
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      clearNextReviewAtMs: clearNextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
      clearLastReviewAtMs: clearLastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore == null
          ? null
          : PlatformInt64Util.from(manualImportanceNudgeScore),
      clearManualImportanceNudgeScore: clearManualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore == null
          ? null
          : PlatformInt64Util.from(manualUrgencyNudgeScore),
      clearManualUrgencyNudgeScore: clearManualUrgencyNudgeScore,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbUpdateTodoStatusWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
      scope: scope.wireValue,
    );
  }

  @override
  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbUpdateTodoDueWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      dueAtMs: PlatformInt64Util.from(dueAtMs),
      scope: scope.wireValue,
    );
  }

  @override
  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) async {
    final appDir = await _getAppDir();
    await _dartDbUpsertTodoRecurrence(
      appDir: appDir,
      key: key,
      todoId: todoId,
      seriesId: seriesId,
      ruleJson: ruleJson,
    );
  }

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbGetTodoRecurrenceRuleJson(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<void> updateTodoRecurrenceRuleWithScope(
    Uint8List key, {
    required String todoId,
    required String ruleJson,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    await _dartDbUpdateTodoRecurrenceRuleWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      ruleJson: ruleJson,
      scope: scope.wireValue,
    );
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    await _dartDbDeleteTodoAndAssociatedMessages(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbAppendTodoNote(
      appDir: appDir,
      key: key,
      todoId: todoId,
      content: content,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbMoveTodoActivity(
      appDir: appDir,
      key: key,
      activityId: activityId,
      toTodoId: toTodoId,
    );
  }

  @override
  Future<TodoChecklistItem> createTodoChecklistItem(
    Uint8List key, {
    required String todoId,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    return _dbCreateTodoChecklistItem(
      appDir: appDir,
      key: key,
      todoId: todoId,
      content: content,
    );
  }

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistItems(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<TodoChecklistItem> updateTodoChecklistItemContent(
    Uint8List key, {
    required String itemId,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpdateTodoChecklistItemContent(
      appDir: appDir,
      key: key,
      itemId: itemId,
      content: content,
    );
  }

  @override
  Future<TodoChecklistItem> setTodoChecklistItemDone(
    Uint8List key, {
    required String itemId,
    required bool isDone,
  }) async {
    final appDir = await _getAppDir();
    return _dbSetTodoChecklistItemDone(
      appDir: appDir,
      key: key,
      itemId: itemId,
      isDone: isDone,
    );
  }

  @override
  Future<void> deleteTodoChecklistItem(
    Uint8List key, {
    required String itemId,
  }) async {
    final appDir = await _getAppDir();
    await _dbDeleteTodoChecklistItem(
      appDir: appDir,
      key: key,
      itemId: itemId,
    );
  }

  @override
  Future<void> reorderTodoChecklistItems(
    Uint8List key, {
    required String todoId,
    required List<String> orderedItemIds,
  }) async {
    final appDir = await _getAppDir();
    await _dbReorderTodoChecklistItems(
      appDir: appDir,
      key: key,
      todoId: todoId,
      orderedItemIds: orderedItemIds,
    );
  }

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistProgress(appDir: appDir, key: key);
  }

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoChecklistSuggestion>> upsertGeneratedTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertGeneratedTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }

  @override
  Future<List<TodoChecklistItem>> applyTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    return _dbApplyTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissAllTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissAllTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoFollowupSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoFollowupSuggestion>> upsertGeneratedTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertGeneratedTodoFollowupSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }

  @override
  Future<bool> upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
    Uint8List key, {
    required String todoId,
    required int jobStartedAtMs,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
      appDir: appDir,
      key: key,
      todoId: todoId,
      jobStartedAtMs: jobStartedAtMs,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }

  @override
  Future<List<TodoActivity>> applyTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    return _dbApplyTodoFollowupSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissTodoFollowupSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissAllTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissAllTodoFollowupSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dartDbListTodoActivities(appDir: appDir, key: key, todoId: todoId);
  }

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbListTodoActivitiesInRange(
      appDir: appDir,
      key: key,
      startAtMsInclusive: PlatformInt64Util.from(startAtMsInclusive),
      endAtMsExclusive: PlatformInt64Util.from(endAtMsExclusive),
    );
  }

  @override
  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) async {
    final appDir = await _getAppDir();
    await _dartDbLinkAttachmentToTodoActivity(
      appDir: appDir,
      key: key,
      activityId: activityId,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async {
    final appDir = await _getAppDir();
    return _dartDbListTodoActivityAttachments(
      appDir: appDir,
      key: key,
      activityId: activityId,
    );
  }
}
