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
}
