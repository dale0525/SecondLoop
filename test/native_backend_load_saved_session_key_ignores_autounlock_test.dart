import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/storage/secure_blob_store.dart';

void main() {
  test('loadSavedSessionKey returns key even if auto-unlock disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final b64 = base64Encode(keyBytes);

    final storage = _InMemorySecureStorage({
      SecureBlobStore.kBlobKey: jsonEncode({
        'auto_unlock_enabled': '0',
        'session_key_b64': b64,
      }),
    });

    final backend = NativeAppBackend(secureStorage: storage);
    final loaded = await backend.loadSavedSessionKey();
    expect(loaded, isNotNull);
    expect(loaded, orderedEquals(keyBytes));
  });
}

final class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage(this._values);

  final Map<String, String> _values;

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
    return Map<String, String>.from(_values);
  }
}

