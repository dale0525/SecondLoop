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
}
