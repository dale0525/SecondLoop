import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('macOS: SyncConfigStore does not touch Keychain for config', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    SharedPreferences.setMockInitialValues({});

    final storage = _CountingSecureStorage();
    final store = SyncConfigStore(storage: storage);

    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('user');
    await store.writeWebdavPassword('pass');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    expect(storage.readCalls, 0);
    expect(storage.writeCalls, 0);
    expect(storage.deleteCalls, 0);

    final config = await store.loadConfiguredSync();
    expect(config, isNotNull);
    expect(config!.backendType, SyncBackendType.webdav);
    expect(config.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNotEmpty);
  });
}

final class _CountingSecureStorage extends FlutterSecureStorage {
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCalls += 1;
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeCalls += 1;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteCalls += 1;
  }
}
