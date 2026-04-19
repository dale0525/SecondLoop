import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../ai/todo_followup_task_classifier.dart';
import '../../features/actions/todo/todo_thread_match.dart';
import '../../src/rust/db.dart';
import '../../src/rust/semantic_parse.dart';
import '../ai/todo_followup_prompt_envelope.dart';

part 'app_backend_prompt_ai.dart';
part 'app_backend_semantic_and_sync.dart';
part 'app_backend_todo_followups.dart';
part 'app_backend_transition_todo.dart';

enum TodoRecurrenceEditScope {
  thisOnly,
  thisAndFuture,
  wholeSeries,
}

extension TodoRecurrenceEditScopeWire on TodoRecurrenceEditScope {
  String get wireValue => switch (this) {
        TodoRecurrenceEditScope.thisOnly => 'this_only',
        TodoRecurrenceEditScope.thisAndFuture => 'this_and_future',
        TodoRecurrenceEditScope.wholeSeries => 'whole_series',
      };
}

abstract class AppBackend with _AppBackendSemanticAndSyncMixin {
  bool get supportsTodoFollowupSuggestions => false;

  bool get autoEnqueuesTodoFollowupGenerationOnCreate => false;

  Future<void> init();

  Future<bool> isMasterPasswordSet();

  Future<bool> readAutoUnlockEnabled();
  Future<void> persistAutoUnlockEnabled({required bool enabled});

  Future<Uint8List?> loadSavedSessionKey();
  Future<void> saveSessionKey(Uint8List key);
  Future<void> clearSavedSessionKey();

  Future<void> validateKey(Uint8List key);

  Future<Uint8List> initMasterPassword(String password);
  Future<Uint8List> unlockWithPassword(String password);

  Future<List<Conversation>> listConversations(Uint8List key);
  Future<Conversation> createConversation(Uint8List key, String title);

  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key);

  Future<List<Message>> listMessages(Uint8List key, String conversationId);
  Future<Message?> getMessageById(Uint8List key, String messageId) {
    throw UnimplementedError('getMessageById');
  }

  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    final messages = await listMessages(key, conversationId);
    final newestFirst = messages.reversed.toList(growable: false);

    if (beforeCreatedAtMs == null && beforeId == null) {
      return newestFirst.take(limit).toList(growable: false);
    }

    if (beforeCreatedAtMs == null || beforeId == null) {
      throw ArgumentError(
          'beforeCreatedAtMs and beforeId must be provided together');
    }

    final cursorIndex = newestFirst.indexWhere((m) => m.id == beforeId);
    if (cursorIndex < 0) return const <Message>[];

    return newestFirst
        .skip(cursorIndex + 1)
        .take(limit)
        .toList(growable: false);
  }

  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  });
  Future<void> editMessage(Uint8List key, String messageId, String content);
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted);
  Future<void> purgeMessageAttachments(Uint8List key, String messageId) =>
      setMessageDeleted(key, messageId, true);

  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key);

  Future<void> clearLocalAttachmentCache(Uint8List key) async {}

  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) {
    throw UnimplementedError('readAttachmentBySha256');
  }

  Future<String> getOrCreateDeviceId() {
    throw UnimplementedError('getOrCreateDeviceId');
  }

  Future<List<Todo>> listTodos(Uint8List key) {
    throw UnimplementedError('listTodos');
  }

  Future<Todo?> getTodoById(Uint8List key, String todoId) {
    throw UnimplementedError('getTodoById');
  }

  Future<List<Todo>> listTodosCreatedInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) {
    throw UnimplementedError('listTodosCreatedInRange');
  }

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
    throw UnimplementedError('upsertTodo');
  }

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
  }) async {
    final todo = await upsertTodo(
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

    final taskTypeHint =
        normalizeTodoFollowupTaskTypeHint(followupTaskTypeHint);
    final taskType = resolveTodoFollowupTaskTypeForCreate(
      title: title,
      followupTaskTypeHint: taskTypeHint,
    );
    final wasCreated = todo.createdAtMs == todo.updatedAtMs;
    if (supportsTodoFollowupSuggestions &&
        !autoEnqueuesTodoFollowupGenerationOnCreate &&
        taskType.allowsAutoFollowup &&
        wasCreated) {
      try {
        await enqueueTodoFollowupGenerationJob(
          key,
          todoId: id,
          triggerKind: 'auto_create',
          taskTypeHint: taskTypeHint,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'AppBackend.upsertTodoFromSemanticCreate follow-up enqueue failed '
          'for $id: $error',
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

    return todo;
  }

  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) {
    throw UnimplementedError('setTodoStatus');
  }

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
  }) =>
      _transitionTodoFallback(
        this,
        key,
        todoId: todoId,
        newStatus: newStatus,
        dueAtMs: dueAtMs,
        clearDueAtMs: clearDueAtMs,
        reviewStage: reviewStage,
        clearReviewStage: clearReviewStage,
        nextReviewAtMs: nextReviewAtMs,
        clearNextReviewAtMs: clearNextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
        clearLastReviewAtMs: clearLastReviewAtMs,
        manualImportanceNudgeScore: manualImportanceNudgeScore,
        clearManualImportanceNudgeScore: clearManualImportanceNudgeScore,
        manualUrgencyNudgeScore: manualUrgencyNudgeScore,
        clearManualUrgencyNudgeScore: clearManualUrgencyNudgeScore,
        sourceMessageId: sourceMessageId,
      );

  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) {
    throw UnimplementedError('updateTodoStatusWithScope');
  }

  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) {
    throw UnimplementedError('updateTodoDueWithScope');
  }

  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) {
    throw UnimplementedError('upsertTodoRecurrence');
  }

  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) {
    throw UnimplementedError('getTodoRecurrenceRuleJson');
  }

  Future<void> updateTodoRecurrenceRuleWithScope(
    Uint8List key, {
    required String todoId,
    required String ruleJson,
    required TodoRecurrenceEditScope scope,
  }) {
    throw UnimplementedError('updateTodoRecurrenceRuleWithScope');
  }

  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    await setTodoStatus(
      key,
      todoId: todoId,
      newStatus: 'dismissed',
    );
  }

  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) {
    throw UnimplementedError('appendTodoNote');
  }

  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) {
    throw UnimplementedError('moveTodoActivity');
  }

  Future<TodoChecklistItem> createTodoChecklistItem(
    Uint8List key, {
    required String todoId,
    required String content,
  }) {
    throw UnimplementedError('createTodoChecklistItem');
  }

  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) {
    throw UnimplementedError('listTodoChecklistItems');
  }

  Future<TodoChecklistItem> updateTodoChecklistItemContent(
    Uint8List key, {
    required String itemId,
    required String content,
  }) {
    throw UnimplementedError('updateTodoChecklistItemContent');
  }

  Future<TodoChecklistItem> setTodoChecklistItemDone(
    Uint8List key, {
    required String itemId,
    required bool isDone,
  }) {
    throw UnimplementedError('setTodoChecklistItemDone');
  }

  Future<void> deleteTodoChecklistItem(
    Uint8List key, {
    required String itemId,
  }) {
    throw UnimplementedError('deleteTodoChecklistItem');
  }

  Future<void> reorderTodoChecklistItems(
    Uint8List key, {
    required String todoId,
    required List<String> orderedItemIds,
  }) {
    throw UnimplementedError('reorderTodoChecklistItems');
  }

  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(Uint8List key) {
    return Future<List<TodoChecklistProgress>>.value(
      const <TodoChecklistProgress>[],
    );
  }

  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) {
    throw UnimplementedError('listTodoChecklistSuggestions');
  }

  Future<List<TodoChecklistSuggestion>> upsertGeneratedTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) {
    throw UnimplementedError('upsertGeneratedTodoChecklistSuggestions');
  }

  Future<List<TodoChecklistItem>> applyTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) {
    throw UnimplementedError('applyTodoChecklistSuggestions');
  }

  Future<void> dismissTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) {
    throw UnimplementedError('dismissTodoChecklistSuggestions');
  }

  Future<void> dismissAllTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
  }) {
    throw UnimplementedError('dismissAllTodoChecklistSuggestions');
  }

  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    Uint8List key,
    String todoId,
  ) {
    throw UnimplementedError('listTodoFollowupSuggestions');
  }

  Future<List<TodoFollowupSuggestion>> upsertGeneratedTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) {
    throw UnimplementedError('upsertGeneratedTodoFollowupSuggestions');
  }

  Future<bool> upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
    Uint8List key, {
    required String todoId,
    required int jobStartedAtMs,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) {
    throw UnimplementedError(
      'upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim',
    );
  }

  Future<List<TodoActivity>> applyTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) {
    throw UnimplementedError('applyTodoFollowupSuggestions');
  }

  Future<void> dismissTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) {
    throw UnimplementedError('dismissTodoFollowupSuggestions');
  }

  Future<void> dismissAllTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
  }) {
    throw UnimplementedError('dismissAllTodoFollowupSuggestions');
  }

  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) {
    throw UnimplementedError('listTodoActivities');
  }

  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) {
    throw UnimplementedError('listTodoActivitiesInRange');
  }

  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) {
    throw UnimplementedError('linkAttachmentToTodoActivity');
  }

  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) {
    throw UnimplementedError('listTodoActivityAttachments');
  }

  Future<List<Event>> listEvents(Uint8List key) {
    throw UnimplementedError('listEvents');
  }

  Future<Event> upsertEvent(
    Uint8List key, {
    required String id,
    required String title,
    required int startAtMs,
    required int endAtMs,
    required String tz,
    String? sourceEntryId,
  }) {
    throw UnimplementedError('upsertEvent');
  }

  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  });

  Future<bool> releaseLocalEmbeddingModelIfIdle(
    Uint8List key, {
    int maxIdleMs = 180000,
  }) async =>
      false;

  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async =>
      0;

  Future<int> processPendingTodoThreadEmbeddingsCloudGateway(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async =>
      processPendingTodoThreadEmbeddings(
        key,
        todoLimit: todoLimit,
        activityLimit: activityLimit,
      );

  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async =>
      processPendingTodoThreadEmbeddings(
        key,
        todoLimit: todoLimit,
        activityLimit: activityLimit,
      );

  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  });

  Future<List<SimilarMessage>> searchSimilarMessagesCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async =>
      searchSimilarMessages(key, query, topK: topK);

  Future<List<SimilarMessage>> searchSimilarMessagesBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      searchSimilarMessages(key, query, topK: topK);

  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <TodoThreadMatch>[];

  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async =>
      searchSimilarTodoThreads(key, query, topK: topK);

  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      searchSimilarTodoThreads(key, query, topK: topK);

  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  });

  Future<List<String>> listEmbeddingModelNames(Uint8List key);
  Future<String> getActiveEmbeddingModelName(Uint8List key);
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName);

  Future<List<LlmProfile>> listLlmProfiles(Uint8List key);
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  });
  Future<void> setActiveLlmProfile(Uint8List key, String profileId);
  Future<void> deleteLlmProfile(Uint8List key, String profileId);

  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) {
    throw UnimplementedError('listEmbeddingProfiles');
  }

  Future<EmbeddingProfile> createEmbeddingProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) {
    throw UnimplementedError('createEmbeddingProfile');
  }

  Future<void> setActiveEmbeddingProfile(Uint8List key, String profileId) {
    throw UnimplementedError('setActiveEmbeddingProfile');
  }

  Future<void> deleteEmbeddingProfile(Uint8List key, String profileId) {
    throw UnimplementedError('deleteEmbeddingProfile');
  }

  Future<List<LlmUsageAggregate>> sumLlmUsageDailyByPurpose(
    Uint8List key,
    String profileId, {
    required String startDay,
    required String endDay,
  }) {
    throw UnimplementedError('sumLlmUsageDailyByPurpose');
  }

  bool get supportsScopedAskAi => false;

  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  });

  Stream<String> askAiStreamWithBrokEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      askAiStream(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
      );

  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('askAiStreamCloudGateway');
  }

  Stream<String> askAiStreamCloudGatewayWithEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) {
    throw UnimplementedError('askAiStreamCloudGatewayWithEmbeddings');
  }

  Stream<String> askAiStreamTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      askAiStream(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
      );

  Stream<String> askAiStreamWithBrokEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      askAiStreamWithBrokEmbeddings(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
      );

  Stream<String> askAiStreamCloudGatewayTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      askAiStreamCloudGateway(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );

  Stream<String> askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) =>
      askAiStreamCloudGatewayWithEmbeddings(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
        embeddingsModelName: embeddingsModelName,
      );

  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) {
    throw UnimplementedError('taskPriorityRerankAi');
  }

  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('taskPriorityRerankAiCloudGateway');
  }

  Future<String> todoFollowupRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('todoFollowupRerankAiCloudGateway');
  }

  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) {
    throw UnimplementedError('fetchTaskPriorityAiAssessmentsCloudGateway');
  }

  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) {
    throw UnimplementedError('upsertTaskPriorityAiAssessmentsCloudGateway');
  }

  Stream<String> askAiStreamScoped(
    Uint8List key,
    String conversationId, {
    required String question,
    required int topK,
    required bool thisThreadOnly,
    int? timeStartMs,
    int? timeEndMs,
    required List<String> includeTagIds,
    required List<String> excludeTagIds,
    required bool strictMode,
    required String localeLanguage,
    required String localDay,
  }) {
    throw UnimplementedError('askAiStreamScoped');
  }

  Stream<String> askAiStreamCloudGatewayScoped(
    Uint8List key,
    String conversationId, {
    required String question,
    required int topK,
    required bool thisThreadOnly,
    int? timeStartMs,
    int? timeEndMs,
    required List<String> includeTagIds,
    required List<String> excludeTagIds,
    required bool strictMode,
    required String localeLanguage,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('askAiStreamCloudGatewayScoped');
  }

  Future<Uint8List> deriveSyncKey(String passphrase);
}

abstract interface class AssistantCitationWriteBackend {
  Future<Message> insertAssistantMessageWithCitations(
    Uint8List key,
    String conversationId, {
    required String content,
    String? citationsJson,
  });
}

abstract interface class DetachedAskCompletionRecoveryBackend {
  Future<bool> applyDetachedAskCompletionOnce(
    Uint8List key, {
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
  });
}

class AppBackendScope extends InheritedWidget {
  const AppBackendScope({
    required this.backend,
    required super.child,
    super.key,
  });

  final AppBackend backend;

  static AppBackend? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppBackendScope>()
        ?.backend;
  }

  static AppBackend of(BuildContext context) {
    final backend = maybeOf(context);
    assert(backend != null, 'No AppBackendScope found in widget tree');
    return backend!;
  }

  @override
  bool updateShouldNotify(AppBackendScope oldWidget) =>
      backend != oldWidget.backend;
}
