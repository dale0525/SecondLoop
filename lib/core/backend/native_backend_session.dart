part of 'native_backend.dart';

mixin _NativeAppBackendSession on _NativeAppBackendAccess {
  @override
  Future<bool> isMasterPasswordSet() async {
    final appDir = await _getAppDir();
    return rust_core.authIsInitialized(appDir: appDir);
  }

  @override
  Future<bool> readAutoUnlockEnabled() async {
    if (_isMacNoKeychain) return false;

    final value = await _secureBlobStore.readValue(
      NativeAppBackend._kAutoUnlockEnabled,
    );
    if (value != null) return value == '1';

    final legacy = await _secureBlobStore.readKey(
      NativeAppBackend._kAutoUnlockEnabled,
    );
    if (legacy == null || legacy.isEmpty) return true;

    await _secureBlobStore.update({
      NativeAppBackend._kAutoUnlockEnabled: legacy,
    });
    await _secureBlobStore.deleteKey(NativeAppBackend._kAutoUnlockEnabled);
    return legacy == '1';
  }

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {
    if (_isMacNoKeychain) return;

    final updates = <String, String?>{
      NativeAppBackend._kAutoUnlockEnabled: enabled ? '1' : '0',
    };
    if (!enabled) {
      updates[NativeAppBackend._kSessionKeyB64] = null;
    }
    await _secureBlobStore.update(updates);
  }

  @override
  Future<Uint8List?> loadSavedSessionKey() async {
    if (_isMacNoKeychain) return null;

    var b64 = await _secureBlobStore.readValue(
      NativeAppBackend._kSessionKeyB64,
    );
    if (b64 == null || b64.isEmpty) {
      final legacy = await _secureBlobStore.readKey(
        NativeAppBackend._kSessionKeyB64,
      );
      if (legacy != null && legacy.isNotEmpty) {
        await _secureBlobStore.update({
          NativeAppBackend._kSessionKeyB64: legacy,
        });
        await _secureBlobStore.deleteKey(NativeAppBackend._kSessionKeyB64);
        b64 = legacy;
      }
    }
    if (b64 == null || b64.isEmpty) return null;

    try {
      final bytes = base64Decode(b64);
      return Uint8List.fromList(bytes);
    } catch (_) {
      await clearSavedSessionKey();
      return null;
    }
  }

  @override
  Future<void> saveSessionKey(Uint8List key) async {
    if (_isMacNoKeychain) return;

    await _secureBlobStore.update({
      NativeAppBackend._kSessionKeyB64: base64Encode(key),
      NativeAppBackend._kAutoUnlockEnabled: '1',
    });
  }

  @override
  Future<void> clearSavedSessionKey() async {
    if (_isMacNoKeychain) return;

    await _secureBlobStore.update({NativeAppBackend._kSessionKeyB64: null});
  }

  @override
  Future<void> validateKey(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.authValidateKey(appDir: appDir, key: key);
  }

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    final appDir = await _getAppDir();
    final prefs = await SharedPreferences.getInstance();
    final deferredPrefsKey = _scopedPrefsKey(
      NativeAppBackend._kDeferredSessionKeyB64PrefsKey,
    );
    final deferredB64 = prefs.getString(deferredPrefsKey);

    Future<Uint8List> init() async {
      if (deferredB64 == null || deferredB64.isEmpty) {
        return rust_core.authInitMasterPassword(
          appDir: appDir,
          password: password,
        );
      }

      try {
        final deferred = base64Decode(deferredB64);
        if (deferred.length != 32) {
          await prefs.remove(deferredPrefsKey);
          return rust_core.authInitMasterPassword(
            appDir: appDir,
            password: password,
          );
        }

        return rust_core.authInitMasterPasswordWithExistingKey(
          appDir: appDir,
          password: password,
          key: deferred,
        );
      } catch (_) {
        await prefs.remove(deferredPrefsKey);
        return rust_core.authInitMasterPassword(
          appDir: appDir,
          password: password,
        );
      }
    }

    final key = await init();
    await prefs.remove(deferredPrefsKey);
    return key;
  }

  @override
  Future<Uint8List> unlockWithPassword(String password) async {
    final appDir = await _getAppDir();
    return rust_core.authUnlockWithPassword(appDir: appDir, password: password);
  }
}
