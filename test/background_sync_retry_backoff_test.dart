import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/background_sync.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/media_backup/cloud_media_backup_runner.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('retryBackoffDelayForFailureCount grows exponentially and caps', () {
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(1),
      const Duration(minutes: 1),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(2),
      const Duration(minutes: 2),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(3),
      const Duration(minutes: 4),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(6),
      const Duration(minutes: 32),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(7),
      const Duration(minutes: 60),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(20),
      const Duration(minutes: 60),
    );
  });

  test('retryable error classification follows sync policy', () {
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 429),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 503),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 401),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 402),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        message: 'SocketException: Failed host lookup',
      ),
      isTrue,
    );
  });

  test('userReadableSyncErrorMessage maps cloud failures', () {
    expect(
      BackgroundSync.userReadableSyncErrorMessage(statusCode: 402),
      contains('subscription'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      contains('read-only'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      contains('quota'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(statusCode: 429),
      contains('Retrying later'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      contains('Local sync data'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        errorMessage:
            'managed-vault v2 recovery blocked: local_media_backfill_pending',
      ),
      contains('backfill'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        errorMessage:
            'managed-vault v2 recovery blocked: local_unpushed_changes',
      ),
      contains('upload'),
    );
  });

  test('managed-vault media uploads only run after a successful final push',
      () {
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: true,
        pullSucceeded: true,
        statusCode: null,
        errorCode: null,
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        pullSucceeded: false,
        statusCode: 402,
        errorCode: 'payment_required',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        pullSucceeded: true,
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        pullSucceeded: false,
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        pullSucceeded: false,
        statusCode: null,
        errorCode: null,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: true,
        pullSucceeded: false,
        statusCode: null,
        errorCode: null,
      ),
      isFalse,
    );
  });

  test(
      'managed-vault background pull-after-push policy matches interactive flows',
      () {
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 409,
        errorCode: 'generation_mismatch',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 409,
        errorCode: 'generation_required',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 402,
        errorCode: 'payment_required',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
  });

  test('invalid managed-vault batches are non-retryable and user visible', () {
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      contains('Local sync data'),
    );
  });

  test('invalid managed-vault batches enter a persistent local-repair block',
      () {
    expect(
      BackgroundSync.shouldBlockBackgroundSyncForFailure(
        backendType: SyncBackendType.managedVault,
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldBlockBackgroundSyncForFailure(
        backendType: SyncBackendType.managedVault,
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldBlockBackgroundSyncForFailure(
        backendType: SyncBackendType.webdav,
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      isFalse,
    );
  });

  test(
      'managed-vault pull-side recovery blockers enter a persistent local-repair block',
      () {
    expect(
      BackgroundSync.shouldBlockBackgroundSyncForResults(
        backendType: SyncBackendType.managedVault,
        pushStatusCode: null,
        pushErrorCode: null,
        pushErrorMessage: null,
        pullStatusCode: null,
        pullErrorCode: null,
        pullErrorMessage:
            'managed-vault v2 recovery blocked: local_media_backfill_pending',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldBlockBackgroundSyncForResults(
        backendType: SyncBackendType.managedVault,
        pushStatusCode: null,
        pushErrorCode: null,
        pushErrorMessage: null,
        pullStatusCode: null,
        pullErrorCode: null,
        pullErrorMessage:
            'managed-vault v2 recovery blocked: local_unpushed_changes',
      ),
      isTrue,
    );
  });

  test('managed-vault background push uses full sync path instead of ops-only',
      () async {
    final backend = _BackgroundManagedVaultPushBackend();
    final result = await BackgroundSync.pushOnceForTest(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      config: SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 2)),
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
      managedVaultIdToken: 'token',
    );

    expect(result.statusCode, isNull);
    expect(backend.managedVaultPushCalls, 1);
    expect(backend.managedVaultPushOpsOnlyCalls, 0);
  });

  test(
      'managed-vault background media uploads are best-effort and preserve pending state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final config = SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 2)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final scopeId = store.syncStateScopeId(config);
    final backend = _ThrowingManagedVaultMediaUploadBackend();

    final hasPendingUploads =
        await BackgroundSync.runManagedVaultMediaUploadsBestEffortForTest(
      backend: backend,
      store: store,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      config: config,
      scopeId: scopeId,
      managedVaultIdToken: 'token',
      wifiOnly: true,
      fallbackPending: true,
      getNetwork: () async => CloudMediaBackupNetwork.wifi,
    );

    expect(hasPendingUploads, isTrue);
    expect(
      await store.readManagedVaultMediaUploadPending(scopeId: scopeId),
      isTrue,
    );
  });

  test(
      'managed-vault background media uploads clear pending state once drained',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final config = SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 2)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final scopeId = store.syncStateScopeId(config);
    await store.writeManagedVaultMediaUploadPending(
      scopeId: scopeId,
      pending: true,
    );
    final backend = _DrainingManagedVaultMediaUploadBackend();

    final hasPendingUploads =
        await BackgroundSync.runManagedVaultMediaUploadsBestEffortForTest(
      backend: backend,
      store: store,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      config: config,
      scopeId: scopeId,
      managedVaultIdToken: 'token',
      wifiOnly: true,
      fallbackPending: true,
      getNetwork: () async => CloudMediaBackupNetwork.wifi,
    );

    expect(hasPendingUploads, isFalse);
    expect(
      await store.readManagedVaultMediaUploadPending(scopeId: scopeId),
      isFalse,
    );
  });
}

final class _BackgroundManagedVaultPushBackend extends TestAppBackend {
  int managedVaultPushCalls = 0;
  int managedVaultPushOpsOnlyCalls = 0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    return 1;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushOpsOnlyCalls++;
    return 1;
  }
}

final class _ThrowingManagedVaultMediaUploadBackend extends TestAppBackend {
  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    return const <CloudMediaBackup>[
      CloudMediaBackup(
        attachmentSha256: 'pending-attachment',
        desiredVariant: 'original',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        updatedAtMs: 0,
      ),
    ];
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    return const CloudMediaBackupSummary(pending: 1, failed: 0, uploaded: 0);
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    throw StateError('upload failed');
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async =>
      0;
}

final class _DrainingManagedVaultMediaUploadBackend extends TestAppBackend {
  bool _uploaded = false;

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    if (_uploaded) {
      return const <CloudMediaBackup>[];
    }
    return const <CloudMediaBackup>[
      CloudMediaBackup(
        attachmentSha256: 'pending-attachment',
        desiredVariant: 'original',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        updatedAtMs: 0,
      ),
    ];
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    return CloudMediaBackupSummary(
      pending: _uploaded ? 0 : 1,
      failed: 0,
      uploaded: _uploaded ? 1 : 0,
    );
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    _uploaded = true;
    return true;
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async =>
      0;
}
