import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../features/actions/todo/todo_thread_match.dart';
import '../../src/rust/db.dart';
import '../../src/rust/semantic_parse.dart';

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

abstract class AppBackend {
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

  Future<String> getOrCreateDeviceId() {
    throw UnimplementedError('getOrCreateDeviceId');
  }

  Future<List<Todo>> listTodos(Uint8List key) {
    throw UnimplementedError('listTodos');
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
  }) {
    throw UnimplementedError('upsertTodo');
  }

  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) {
    throw UnimplementedError('setTodoStatus');
  }

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

  Future<String> semanticParseMessageAction(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
  }) {
    throw UnimplementedError('semanticParseMessageAction');
  }

  Future<String> semanticParseMessageActionCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('semanticParseMessageActionCloudGateway');
  }

  Future<String> semanticParseAskAiTimeWindow(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) {
    throw UnimplementedError('semanticParseAskAiTimeWindow');
  }

  Future<String> semanticParseAskAiTimeWindowCloudGateway(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    throw UnimplementedError('semanticParseAskAiTimeWindowCloudGateway');
  }

  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('enqueueSemanticParseJob');
  }

  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) {
    throw UnimplementedError('listDueSemanticParseJobs');
  }

  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) {
    throw UnimplementedError('listSemanticParseJobsByMessageIds');
  }

  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobRunning');
  }

  Future<void> markSemanticParseJobFailed(
    Uint8List key, {
    required String messageId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobFailed');
  }

  Future<void> markSemanticParseJobRetry(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobRetry');
  }

  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobSucceeded');
  }

  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobCanceled');
  }

  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobUndone');
  }

  Future<Uint8List> deriveSyncKey(String passphrase);

  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    throw UnimplementedError('syncWebdavPushOpsOnly');
  }

  Stream<String> syncWebdavPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncWebdavPushOpsOnly(
      key,
      syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    yield '{"type":"result","count":$pushed}';
  }

  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Stream<String> syncWebdavPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pulled = await syncWebdavPull(
      key,
      syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    yield '{"type":"result","count":$pulled}';
  }

  Future<void> syncWebdavDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) {
    throw UnimplementedError('syncWebdavDownloadAttachmentBytes');
  }

  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) {
    throw UnimplementedError('syncWebdavUploadAttachmentBytes');
  }

  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  });

  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  });

  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  });

  Stream<String> syncLocaldirPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncLocaldirPush(
      key,
      syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    yield '{"type":"result","count":$pushed}';
  }

  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  });

  Stream<String> syncLocaldirPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pulled = await syncLocaldirPull(
      key,
      syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    yield '{"type":"result","count":$pulled}';
  }

  Future<void> syncLocaldirDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
    required String sha256,
  }) {
    throw UnimplementedError('syncLocaldirDownloadAttachmentBytes');
  }

  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    throw UnimplementedError('syncManagedVaultPush');
  }

  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    throw UnimplementedError('syncManagedVaultPull');
  }

  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pulled = await syncManagedVaultPull(
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
    yield '{"type":"result","count":$pulled}';
  }

  Future<void> syncManagedVaultDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) {
    throw UnimplementedError('syncManagedVaultDownloadAttachmentBytes');
  }

  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    throw UnimplementedError('syncManagedVaultPushOpsOnly');
  }

  Stream<String> syncManagedVaultPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncManagedVaultPushOpsOnly(
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
    yield '{"type":"result","count":$pushed}';
  }

  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) {
    throw UnimplementedError('syncManagedVaultUploadAttachmentBytes');
  }

  Future<void> syncManagedVaultClearDevice({
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String deviceId,
  }) {
    throw UnimplementedError('syncManagedVaultClearDevice');
  }

  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    throw UnimplementedError('syncManagedVaultClearVault');
  }

  Future<AttachmentVariant> upsertAttachmentVariant(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
    required Uint8List bytes,
    required String mimeType,
  }) {
    throw UnimplementedError('upsertAttachmentVariant');
  }

  Future<Uint8List> readAttachmentVariantBytes(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
  }) {
    throw UnimplementedError('readAttachmentVariantBytes');
  }

  Future<void> enqueueCloudMediaBackup(
    Uint8List key, {
    required String attachmentSha256,
    required String desiredVariant,
    required int nowMs,
  }) {
    throw UnimplementedError('enqueueCloudMediaBackup');
  }

  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
  }) {
    throw UnimplementedError('backfillCloudMediaBackupImages');
  }

  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
  }) {
    throw UnimplementedError('listDueCloudMediaBackups');
  }

  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) {
    throw UnimplementedError('markCloudMediaBackupFailed');
  }

  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
  }) {
    throw UnimplementedError('markCloudMediaBackupUploaded');
  }

  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) {
    throw UnimplementedError('cloudMediaBackupSummary');
  }
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
