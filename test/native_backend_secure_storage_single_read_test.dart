import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';

void main() {
  test('loadSavedSessionKey uses a single secure read (blob)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final b64 = base64Encode(keyBytes);

    final storage = _CountingSecureStorage({
      'auto_unlock_enabled': '1',
      'session_key_b64': b64,
      'sync_config_blob_json_v1': jsonEncode({
        'auto_unlock_enabled': '1',
        'session_key_b64': b64,
      }),
    });

    final backend = NativeAppBackend(secureStorage: storage);

    final loaded = await backend.loadSavedSessionKey();
    expect(loaded, isNotNull);
    expect(loaded, orderedEquals(keyBytes));

    expect(storage.readCalls, 1);
    expect(storage.writeCalls, 0);
    expect(storage.deleteCalls, 0);
  });
}

final class _CountingSecureStorage extends FlutterSecureStorage {
  _CountingSecureStorage(this._values);

  final Map<String, String> _values;

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
    return _values[key];
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
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
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
    _values.remove(key);
  }
}
