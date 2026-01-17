import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('loadConfiguredSync reads config from preferences blob', () async {
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kAutoEnabled: '1',
        SyncConfigStore.kRemoteRoot: 'SecondLoop',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/dav',
        SyncConfigStore.kSyncKeyB64: base64Encode(syncKey),
      }),
    });

    final store = SyncConfigStore();
    final config = await store.loadConfiguredSync();

    expect(config, isNotNull);
    expect(config!.backendType, SyncBackendType.webdav);
    expect(config.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');
  });
}
