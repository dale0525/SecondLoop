import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('SyncConfigStore splits public and secret preferences entries',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();

    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('user');
    await store.writeWebdavPassword('pass');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().length, 2);
  });
}
