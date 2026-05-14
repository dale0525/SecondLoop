part of 'app_backend.dart';

mixin _AppBackendSemanticAndSyncMixin {
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

  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    bool manualOverrideFollowup = false,
    String? taskTypeHint,
    required int nowMs,
  }) {
    throw UnimplementedError('enqueueTodoFollowupGenerationJob');
  }

  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) {
    throw UnimplementedError('listDueTodoFollowupGenerationJobs');
  }

  Future<TodoFollowupGenerationJob?> getTodoFollowupGenerationJob(
    Uint8List key,
    String todoId,
  ) {
    throw UnimplementedError('getTodoFollowupGenerationJob');
  }

  Future<void> markTodoFollowupGenerationJobRunning(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError('markTodoFollowupGenerationJobRunning');
  }

  Future<void> markTodoFollowupGenerationJobFailed(
    Uint8List key, {
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) {
    throw UnimplementedError('markTodoFollowupGenerationJobFailed');
  }

  Future<void> markTodoFollowupGenerationJobSucceeded(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError('markTodoFollowupGenerationJobSucceeded');
  }

  Future<void> markTodoFollowupGenerationJobSkipped(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError('markTodoFollowupGenerationJobSkipped');
  }

  Future<void> markTodoFollowupGenerationJobCanceled(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError('markTodoFollowupGenerationJobCanceled');
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
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
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

  Future<int> requeueRunningSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
  }) {
    throw UnimplementedError('requeueRunningSemanticParseJobs');
  }

  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) {
    throw UnimplementedError('markSemanticParseJobUndone');
  }

  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) {
    throw UnimplementedError('createSyncRecoveryEnvelope');
  }

  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) {
    throw UnimplementedError('recoverSyncKeyFromEnvelope');
  }

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

  Future<int> syncManagedVaultBlobRepairQueueDepth({
    required String baseUrl,
    required String vaultId,
  }) async {
    return 0;
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

  Stream<String> syncManagedVaultPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncManagedVaultPush(
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
    String? scopeId,
  }) {
    throw UnimplementedError('enqueueCloudMediaBackup');
  }

  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) {
    throw UnimplementedError('backfillCloudMediaBackupImages');
  }

  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
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
    String? scopeId,
  }) {
    throw UnimplementedError('markCloudMediaBackupFailed');
  }

  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) {
    throw UnimplementedError('markCloudMediaBackupUploaded');
  }

  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) {
    throw UnimplementedError('cloudMediaBackupSummary');
  }

  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    throw UnimplementedError('createVaultRollbackSnapshot');
  }

  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) {
    throw UnimplementedError('restoreVaultRollbackSnapshot');
  }

  Future<void> deleteVaultRollbackSnapshot({required String snapshotPath}) {
    throw UnimplementedError('deleteVaultRollbackSnapshot');
  }
}
