import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('loadConfiguredSync uses batched readAll', () async {
    final storage = _CountingSecureStorage({
      SyncConfigStore.kSyncKeyB64:
          base64Encode(Uint8List.fromList(List<int>.filled(32, 1))),
      SyncConfigStore.kRemoteRoot: 'SecondLoop',
      SyncConfigStore.kBackendType: 'webdav',
      SyncConfigStore.kWebdavBaseUrl: 'https://example.com/dav',
    });

    final store = SyncConfigStore(storage: storage);
    final config = await store.loadConfiguredSync();

    expect(config, isNotNull);
    expect(config!.backendType, SyncBackendType.webdav);
    expect(config.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');

    expect(storage.readAllCalls, 1);
    expect(storage.readCalls, 0);
  });
}

final class _CountingSecureStorage extends FlutterSecureStorage {
  _CountingSecureStorage(this._values);

  final Map<String, String> _values;

  int readCalls = 0;
  int readAllCalls = 0;

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
    return _values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCalls += 1;
    return Map<String, String>.from(_values);
  }
}

