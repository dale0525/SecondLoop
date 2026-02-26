import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_secret_store.dart';

void main() {
  test('migrates sensitive fields out of public config blob', () async {
    final syncKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    SharedPreferences.setMockInitialValues({
      SyncConfigStore.legacyPrefsBlobKeyForTest: jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kAutoEnabled: '1',
        SyncConfigStore.kRemoteRoot: 'SecondLoop',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/dav',
        SyncConfigStore.kWebdavUsername: 'u1',
        SyncConfigStore.kWebdavPassword: 'plain-password',
        SyncConfigStore.kSyncKeyB64: base64Encode(syncKey),
      }),
    });

    final store = SyncConfigStore();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.webdav);
    expect(configured.baseUrl, 'https://example.com/dav');
    expect(configured.username, 'u1');
    expect(configured.password, 'plain-password');
    expect(configured.syncKey, syncKey);

    final publicMap = await store.readAll();
    expect(publicMap.containsKey(SyncConfigStore.kWebdavPassword), isFalse);
    expect(publicMap.containsKey(SyncConfigStore.kSyncKeyB64), isFalse);

    final secretStore = SyncSecretStore();
    expect(await secretStore.readWebdavPassword(), 'plain-password');
    expect(await secretStore.readSyncKey(), syncKey);

    final prefs = await SharedPreferences.getInstance();
    final migratedRaw = prefs.getString(SyncConfigStore.prefsBlobKeyForTest);
    expect(migratedRaw, isNotNull);
    expect(prefs.getString(SyncConfigStore.legacyPrefsBlobKeyForTest), isNull);
    expect(
      prefs.getInt(SyncConfigStore.syncSecretStoreVersionPrefsKeyForTest),
      1,
    );
    expect(migratedRaw, isNot(contains('plain-password')));

    final migratedMap = jsonDecode(migratedRaw!) as Map<String, dynamic>;
    expect(
      migratedMap.containsKey(SyncConfigStore.kWebdavPassword),
      isFalse,
    );
    expect(
      migratedMap.containsKey(SyncConfigStore.kSyncKeyB64),
      isFalse,
    );
  });

  test('new writes keep sensitive fields in secret store only', () async {
    SharedPreferences.setMockInitialValues({});

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u1');
    await store.writeWebdavPassword('p1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final publicMap = await store.readAll();
    expect(publicMap.containsKey(SyncConfigStore.kWebdavPassword), isFalse);
    expect(publicMap.containsKey(SyncConfigStore.kSyncKeyB64), isFalse);

    final secretStore = SyncSecretStore();
    expect(await secretStore.readWebdavPassword(), 'p1');
    expect(await secretStore.readSyncKey(),
        Uint8List.fromList(List<int>.filled(32, 7)));

    final prefs = await SharedPreferences.getInstance();
    final publicRaw =
        prefs.getString(SyncConfigStore.prefsBlobKeyForTest) ?? '';
    expect(publicRaw, isNot(contains('p1')));
    expect(publicRaw, isNot(contains(base64Encode(List<int>.filled(32, 7)))));
    expect(prefs.getString(SyncConfigStore.legacyPrefsBlobKeyForTest), isNull);

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.password, 'p1');
    expect(configured.syncKey, Uint8List.fromList(List<int>.filled(32, 7)));
  });
}
