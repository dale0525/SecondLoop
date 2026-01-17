import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/native_backend.dart';

void main() {
  test('macOS: session key persists in secure storage (not prefs)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    SharedPreferences.setMockInitialValues({});

    final secureStorage = _InMemorySecureStorage({});
    final backend = NativeAppBackend(secureStorage: secureStorage);

    final key = Uint8List.fromList(List<int>.filled(32, 7));
    await backend.saveSessionKey(key);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_key_b64_v1'), isNull);
    expect(prefs.getBool('auto_unlock_enabled_v1'), isNull);

    final freshBackend = NativeAppBackend(secureStorage: secureStorage);
    final loaded = await freshBackend.loadSavedSessionKey();
    expect(loaded, isNotNull);
    expect(loaded, orderedEquals(key));

    expect(secureStorage.readCalls, greaterThan(0));
    expect(secureStorage.writeCalls, greaterThan(0));
  });
}

final class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage(this._values);

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
