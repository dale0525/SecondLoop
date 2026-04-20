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
    final scopeA = store.backgroundSyncScopeId(configA);
    final scopeB = store.backgroundSyncScopeId(configB);

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
    final scopeA = store.backgroundSyncScopeId(configA);
    final scopeB = store.backgroundSyncScopeId(configB);

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
}
