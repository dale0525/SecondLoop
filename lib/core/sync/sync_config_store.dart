import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_engine.dart';

final class SyncConfigStore {
  SyncConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _createDefaultSecureStorage();

  final FlutterSecureStorage _storage;

  static const List<String> _knownKeys = [
    kBackendType,
    kAutoEnabled,
    kLocalDir,
    kWebdavBaseUrl,
    kWebdavUsername,
    kWebdavPassword,
    kRemoteRoot,
    kSyncKeyB64,
  ];

  static const kBackendType = 'sync_backend_type'; // webdav | localdir
  static const kAutoEnabled = 'sync_auto_enabled'; // 1 | 0
  static const kLocalDir = 'sync_localdir_path';

  static const kWebdavBaseUrl = 'sync_webdav_base_url';
  static const kWebdavUsername = 'sync_webdav_username';
  static const kWebdavPassword = 'sync_webdav_password';
  static const kRemoteRoot = 'sync_webdav_remote_root';
  static const kSyncKeyB64 = 'sync_webdav_sync_key_b64';

  static FlutterSecureStorage _createDefaultSecureStorage() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(),
      );
    }
    return const FlutterSecureStorage();
  }

  Future<bool> readAutoEnabled() async {
    final v = await _safeRead(kAutoEnabled);
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeAutoEnabled(bool enabled) async {
    await _safeWrite(kAutoEnabled, enabled ? '1' : '0');
  }

  Future<SyncBackendType> readBackendType() async {
    final v = await _safeRead(kBackendType);
    return switch (v) {
      'localdir' => SyncBackendType.localDir,
      _ => SyncBackendType.webdav,
    };
  }

  Future<void> writeBackendType(SyncBackendType type) async {
    final v = type == SyncBackendType.localDir ? 'localdir' : 'webdav';
    await _safeWrite(kBackendType, v);
  }

  Future<Uint8List?> readSyncKey() async {
    final b64 = await _safeRead(kSyncKeyB64);
    if (b64 == null || b64.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _safeWrite(kSyncKeyB64, base64Encode(key));
  }

  Future<String?> readWebdavBaseUrl() async => _safeRead(kWebdavBaseUrl);
  Future<String?> readWebdavUsername() async => _safeRead(kWebdavUsername);
  Future<String?> readWebdavPassword() async => _safeRead(kWebdavPassword);
  Future<String?> readRemoteRoot() async => _safeRead(kRemoteRoot);
  Future<String?> readLocalDir() async => _safeRead(kLocalDir);

  Future<void> writeWebdavBaseUrl(String baseUrl) async =>
      _safeWrite(kWebdavBaseUrl, baseUrl);
  Future<void> writeRemoteRoot(String remoteRoot) async =>
      _safeWrite(kRemoteRoot, remoteRoot);

  Future<void> writeWebdavUsername(String? username) async {
    if (username == null || username.isEmpty) {
      await _safeDelete(kWebdavUsername);
      return;
    }
    await _safeWrite(kWebdavUsername, username);
  }

  Future<void> writeWebdavPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _safeDelete(kWebdavPassword);
      return;
    }
    await _safeWrite(kWebdavPassword, password);
  }

  Future<void> writeLocalDir(String? localDir) async {
    if (localDir == null || localDir.isEmpty) {
      await _safeDelete(kLocalDir);
      return;
    }
    await _safeWrite(kLocalDir, localDir);
  }

  Future<SyncConfig?> loadConfiguredSync() async {
    final all = await _safeReadAll();
    if (all == null || all.isEmpty) return null;

    final b64 = all[kSyncKeyB64];
    if (b64 == null || b64.isEmpty) return null;

    Uint8List? syncKey;
    try {
      syncKey = Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      syncKey = null;
    }
    if (syncKey == null || syncKey.length != 32) return null;

    final remoteRoot = all[kRemoteRoot]?.trim();
    if (remoteRoot == null || remoteRoot.isEmpty) return null;

    final backendType = switch (all[kBackendType]) {
      'localdir' => SyncBackendType.localDir,
      _ => SyncBackendType.webdav,
    };
    switch (backendType) {
      case SyncBackendType.webdav:
        final baseUrl = all[kWebdavBaseUrl]?.trim();
        if (baseUrl == null || baseUrl.isEmpty) return null;
        final username = all[kWebdavUsername]?.trim();
        final password = all[kWebdavPassword];
        return SyncConfig.webdav(
          syncKey: syncKey,
          remoteRoot: remoteRoot,
          baseUrl: baseUrl,
          username: username == null || username.isEmpty ? null : username,
          password: password == null || password.isEmpty ? null : password,
        );
      case SyncBackendType.localDir:
        final localDir = all[kLocalDir]?.trim();
        if (localDir == null || localDir.isEmpty) return null;
        return SyncConfig.localDir(
          syncKey: syncKey,
          remoteRoot: remoteRoot,
          localDir: localDir,
        );
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null || defaultTargetPlatform != TargetPlatform.macOS) return v;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return null;
    try {
      final legacy = await _storage.read(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
      if (legacy == null) return null;

      await _safeWrite(key, legacy);
      return legacy;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<String, String>?> _safeReadAll() async {
    try {
      final primary = await _storage.readAll();
      if (defaultTargetPlatform != TargetPlatform.macOS) return primary;

      final legacy = await _storage.readAll(
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
      if (legacy.isEmpty) return primary;

      final merged = <String, String>{...primary};
      for (final key in _knownKeys) {
        if (merged.containsKey(key)) continue;
        final legacyValue = legacy[key];
        if (legacyValue == null) continue;
        merged[key] = legacyValue;
        await _safeWrite(key, legacyValue);
      }

      return merged;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _storage.delete(
          key: key,
          mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
        );
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      if (defaultTargetPlatform != TargetPlatform.macOS) return;
      try {
        await _storage.write(
          key: key,
          value: value,
          mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
        );
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _storage.delete(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
    } catch (_) {
      return;
    }
  }
}
