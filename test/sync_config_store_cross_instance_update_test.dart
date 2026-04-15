import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('SyncConfigStore notices updates from other instances', () async {
    SharedPreferences.setMockInitialValues({});

    final staleReader = SyncConfigStore();
    expect(await staleReader.loadConfiguredSyncIfAutoEnabled(), isNull);

    final writer = SyncConfigStore();
    await writer.writeBackendType(SyncBackendType.webdav);
    await writer.writeAutoEnabled(true);
    await writer.writeRemoteRoot('SecondLoop');
    await writer.writeWebdavBaseUrl('https://example.com/dav');
    await writer.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final config = await staleReader.loadConfiguredSyncIfAutoEnabled();
    expect(config, isNotNull);
    expect(config!.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');
  });

  test('SyncConfigStore rollout flags default enabled and sync cross-instance',
      () async {
    SharedPreferences.setMockInitialValues({});

    final staleReader = SyncConfigStore();
    expect(await staleReader.readSyncRefreshV2Enabled(), isTrue);
    expect(await staleReader.readSyncBackgroundDiagV1Enabled(), isTrue);
    expect(await staleReader.readSyncBackoffV1Enabled(), isTrue);

    final writer = SyncConfigStore();
    await writer.writeSyncRefreshV2Enabled(false);
    await writer.writeSyncBackgroundDiagV1Enabled(false);
    await writer.writeSyncBackoffV1Enabled(false);

    expect(await staleReader.readSyncRefreshV2Enabled(), isFalse);
    expect(await staleReader.readSyncBackgroundDiagV1Enabled(), isFalse);
    expect(await staleReader.readSyncBackoffV1Enabled(), isFalse);
  });

  test('SyncConfigStore isolates scoped data between users', () async {
    SharedPreferences.setMockInitialValues({});

    final first = SyncConfigStore(scopeKey: 'web-native:uid-1');
    final second = SyncConfigStore(scopeKey: 'web-native:uid-2');

    await first.writeBackendType(SyncBackendType.managedVault);
    await first.writeRemoteRoot('uid-1');
    await first.writeManagedVaultBaseUrl('https://vault-1.example');
    await first.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await second.writeBackendType(SyncBackendType.managedVault);
    await second.writeRemoteRoot('uid-2');
    await second.writeManagedVaultBaseUrl('https://vault-2.example');
    await second.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 2)));

    expect(await first.readRemoteRoot(), 'uid-1');
    expect(await second.readRemoteRoot(), 'uid-2');
    expect(await first.resolveManagedVaultBaseUrl(), 'https://vault-1.example');
    expect(
      await second.resolveManagedVaultBaseUrl(),
      'https://vault-2.example',
    );
    expect(
        await first.readSyncKey(), Uint8List.fromList(List<int>.filled(32, 1)));
    expect(await second.readSyncKey(),
        Uint8List.fromList(List<int>.filled(32, 2)));
  });
}
