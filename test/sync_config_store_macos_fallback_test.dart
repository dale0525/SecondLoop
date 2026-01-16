import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('macOS: falls back to legacy keychain when primary secure storage fails',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final storage = _MacOsSplitSecureStorage();
    final store = SyncConfigStore(storage: storage);

    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final config = await store.loadConfiguredSync();
    expect(config, isNotNull);
    expect(config!.backendType, SyncBackendType.webdav);
    expect(config.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');
  });
}

final class _MacOsSplitSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _legacy = {};

  bool _isLegacy(MacOsOptions? mOptions) => mOptions != null;

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
    if (_isLegacy(mOptions)) return _legacy[key];
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
    if (_isLegacy(mOptions)) {
      final v = value;
      if (v == null) {
        _legacy.remove(key);
        return;
      }
      _legacy[key] = v;
      return;
    }
    throw PlatformException(code: 'secure_storage_failed');
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
    if (_isLegacy(mOptions)) {
      _legacy.remove(key);
    }
  }
}
