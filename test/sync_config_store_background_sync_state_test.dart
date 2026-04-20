import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_diagnostics.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('SyncConfigStore persists background sync result', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();

    const result = SyncBackgroundResult(
      backendType: SyncBackendType.managedVault,
      direction: SyncBackgroundDirection.pull,
      status: SyncBackgroundResultStatus.failure,
      timestampMs: 123,
      statusCode: 429,
      errorCode: 'rate_limited',
      errorMessage: 'managed-vault pull failed: HTTP 429',
      userMessage: 'Sync is being throttled. Retrying later.',
      retryCount: 2,
      durationMs: 520,
    );

    await store.writeBackgroundSyncResult(
      result,
      backendType: SyncBackendType.managedVault,
    );

    final restored = await store.readBackgroundSyncResult(
      backendType: SyncBackendType.managedVault,
    );
    expect(restored, isNotNull);
    expect(restored!.backendType, SyncBackendType.managedVault);
    expect(restored.direction, SyncBackgroundDirection.pull);
    expect(restored.status, SyncBackgroundResultStatus.failure);
    expect(restored.statusCode, 429);
    expect(restored.errorCode, 'rate_limited');
    expect(restored.retryCount, 2);
    expect(restored.durationMs, 520);
  });

  test('SyncConfigStore scopes background sync result by config', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final configA = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-a',
      baseUrl: 'https://vault-a.example.com',
    );
    final configB = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-b',
      baseUrl: 'https://vault-b.example.com',
    );
    final scopeA = store.syncStateScopeId(configA);
    final scopeB = store.syncStateScopeId(configB);

    const result = SyncBackgroundResult(
      backendType: SyncBackendType.managedVault,
      direction: SyncBackgroundDirection.pull,
      status: SyncBackgroundResultStatus.failure,
      timestampMs: 123,
      statusCode: 429,
      errorCode: 'rate_limited',
      errorMessage: 'managed-vault pull failed: HTTP 429',
      userMessage: 'Sync is being throttled. Retrying later.',
      retryCount: 2,
      durationMs: 520,
    );

    await store.writeBackgroundSyncResult(
      result,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeA,
    );

    expect(
      await store.readBackgroundSyncResult(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeA,
      ),
      isNotNull,
    );
    expect(
      await store.readBackgroundSyncResult(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeB,
      ),
      isNull,
    );
  });

  test('SyncConfigStore persists background sync backoff state', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();

    const state = SyncBackgroundBackoffState(
      backendType: SyncBackendType.webdav,
      retryCount: 3,
      nextAllowedAtMs: 1000,
      updatedAtMs: 200,
      lastStatusCode: 503,
      lastErrorCode: 'server_error',
    );

    await store.writeBackgroundSyncBackoffState(
      state,
      backendType: SyncBackendType.webdav,
    );

    final restored = await store.readBackgroundSyncBackoffState(
      backendType: SyncBackendType.webdav,
    );
    expect(restored, isNotNull);
    expect(restored!.backendType, SyncBackendType.webdav);
    expect(restored.retryCount, 3);
    expect(restored.nextAllowedAtMs, 1000);
    expect(restored.lastStatusCode, 503);
    expect(restored.lastErrorCode, 'server_error');

    await store.writeBackgroundSyncBackoffState(
      null,
      backendType: SyncBackendType.webdav,
    );
    final cleared = await store.readBackgroundSyncBackoffState(
      backendType: SyncBackendType.webdav,
    );
    expect(cleared, isNull);
  });

  test('SyncConfigStore persists background sync local repair block state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();

    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
    );

    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
      ),
      isTrue,
    );

    await store.writeBackgroundSyncRepairRequired(
      false,
      backendType: SyncBackendType.managedVault,
    );

    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
      ),
      isFalse,
    );
  });

  test(
      'SyncConfigStore scopes background sync backoff and repair state by config',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final configA = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-a',
      baseUrl: 'https://vault-a.example.com',
    );
    final configB = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-b',
      baseUrl: 'https://vault-b.example.com',
    );
    final scopeA = store.syncStateScopeId(configA);
    final scopeB = store.syncStateScopeId(configB);

    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 2,
        nextAllowedAtMs: 1234,
        updatedAtMs: 1200,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeA,
    );
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeA,
    );

    expect(
      await store.readBackgroundSyncBackoffState(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeA,
      ),
      isNotNull,
    );
    expect(
      await store.readBackgroundSyncBackoffState(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeB,
      ),
      isNull,
    );
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeA,
      ),
      isTrue,
    );
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeB,
      ),
      isFalse,
    );
  });

  test(
      'SyncConfigStore reads legacy unscoped background state for scoped callers',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final config = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-a',
      baseUrl: 'https://vault-a.example.com',
    );
    final scopeId = store.syncStateScopeId(config);

    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 4,
        nextAllowedAtMs: 4321,
        updatedAtMs: 4300,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
    );
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
    );

    final restoredBackoff = await store.readBackgroundSyncBackoffState(
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
    final restoredRepair = await store.readBackgroundSyncRepairRequired(
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    expect(restoredBackoff, isNotNull);
    expect(restoredBackoff!.retryCount, 4);
    expect(restoredBackoff.nextAllowedAtMs, 4321);
    expect(restoredRepair, isTrue);
  });

  test('SyncConfigStore no-scope reads return latest scoped diagnostics state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final scopeA = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-a',
        baseUrl: 'https://vault-a.example.com',
      ),
    );
    final scopeB = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-b',
        baseUrl: 'https://vault-b.example.com',
      ),
    );

    await store.writeBackgroundSyncResult(
      const SyncBackgroundResult(
        backendType: SyncBackendType.managedVault,
        direction: SyncBackgroundDirection.pull,
        status: SyncBackgroundResultStatus.failure,
        timestampMs: 100,
        statusCode: 429,
        errorCode: 'rate_limited',
        errorMessage: 'old',
        userMessage: 'old',
        retryCount: 1,
        durationMs: 10,
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeA,
    );
    await store.writeBackgroundSyncResult(
      const SyncBackgroundResult(
        backendType: SyncBackendType.managedVault,
        direction: SyncBackgroundDirection.push,
        status: SyncBackgroundResultStatus.success,
        timestampMs: 200,
        statusCode: null,
        errorCode: null,
        errorMessage: null,
        userMessage: null,
        retryCount: null,
        durationMs: 20,
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeB,
    );
    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 1,
        nextAllowedAtMs: 1111,
        updatedAtMs: 1100,
        lastStatusCode: 429,
        lastErrorCode: 'rate_limited',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeA,
    );
    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 5,
        nextAllowedAtMs: 5555,
        updatedAtMs: 5500,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeB,
    );
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeB,
    );

    final result = await store.readBackgroundSyncResult(
      backendType: SyncBackendType.managedVault,
    );
    final backoff = await store.readBackgroundSyncBackoffState(
      backendType: SyncBackendType.managedVault,
    );
    final repairRequired = await store.readBackgroundSyncRepairRequired(
      backendType: SyncBackendType.managedVault,
    );

    expect(result, isNotNull);
    expect(result!.timestampMs, 200);
    expect(result.direction, SyncBackgroundDirection.push);
    expect(backoff, isNotNull);
    expect(backoff!.retryCount, 5);
    expect(backoff.nextAllowedAtMs, 5555);
    expect(repairRequired, isTrue);
  });

  test('SyncConfigStore differentiates WebDAV scope by username', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 3));
    final configA = SyncConfig.webdav(
      syncKey: syncKey,
      remoteRoot: 'SecondLoop',
      baseUrl: 'https://dav.example.com',
      username: 'alice',
      password: 'pw-a',
    );
    final configB = SyncConfig.webdav(
      syncKey: syncKey,
      remoteRoot: 'SecondLoop',
      baseUrl: 'https://dav.example.com',
      username: 'bob',
      password: 'pw-b',
    );

    expect(
      store.syncStateScopeId(configA),
      isNot(store.syncStateScopeId(configB)),
    );
  });

  test('SyncConfigStore differentiates managed-vault scope by sync key',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final configA = SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final configB = SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 2)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );

    expect(
      store.syncStateScopeId(configA),
      isNot(store.syncStateScopeId(configB)),
    );
  });
}
