import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../features/actions/todo/todo_thread_match.dart';
import '../../src/rust/db.dart';

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

  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key);

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

  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  });

  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <TodoThreadMatch>[];

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

  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

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

  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  });

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

  static AppBackend of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppBackendScope>();
    assert(scope != null, 'No AppBackendScope found in widget tree');
    return scope!.backend;
  }

  @override
  bool updateShouldNotify(AppBackendScope oldWidget) =>
      backend != oldWidget.backend;
}
