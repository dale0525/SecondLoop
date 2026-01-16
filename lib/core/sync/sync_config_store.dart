import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_engine.dart';

final class SyncConfigStore {
  SyncConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _createDefaultSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kConfigBlobKey = 'sync_config_blob_json_v1';

  static const List<String> _knownKeys = [
    _kConfigBlobKey,
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

  Future<Map<String, String>> readAll() async {
    return _loadConfigMap();
  }

  Future<bool> readAutoEnabled() async {
    final v = (await _loadConfigMap())[kAutoEnabled];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeAutoEnabled(bool enabled) async {
    await _writeConfigUpdates({kAutoEnabled: enabled ? '1' : '0'});
  }

  Future<SyncBackendType> readBackendType() async {
    final v = (await _loadConfigMap())[kBackendType];
    return switch (v) {
      'localdir' => SyncBackendType.localDir,
      _ => SyncBackendType.webdav,
    };
  }

  Future<void> writeBackendType(SyncBackendType type) async {
    final v = type == SyncBackendType.localDir ? 'localdir' : 'webdav';
    await _writeConfigUpdates({kBackendType: v});
  }

  Future<Uint8List?> readSyncKey() async {
    final b64 = (await _loadConfigMap())[kSyncKeyB64];
    if (b64 == null || b64.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _writeConfigUpdates({kSyncKeyB64: base64Encode(key)});
  }

  Future<String?> readWebdavBaseUrl() async =>
      (await _loadConfigMap())[kWebdavBaseUrl];
  Future<String?> readWebdavUsername() async =>
      (await _loadConfigMap())[kWebdavUsername];
  Future<String?> readWebdavPassword() async =>
      (await _loadConfigMap())[kWebdavPassword];
  Future<String?> readRemoteRoot() async =>
      (await _loadConfigMap())[kRemoteRoot];
  Future<String?> readLocalDir() async => (await _loadConfigMap())[kLocalDir];

  Future<void> writeWebdavBaseUrl(String baseUrl) async =>
      _writeConfigUpdates({kWebdavBaseUrl: baseUrl});
  Future<void> writeRemoteRoot(String remoteRoot) async =>
      _writeConfigUpdates({kRemoteRoot: remoteRoot});

  Future<void> writeWebdavUsername(String? username) async {
    if (username == null || username.isEmpty) {
      await _writeConfigUpdates({kWebdavUsername: null});
      return;
    }
    await _writeConfigUpdates({kWebdavUsername: username});
  }

  Future<void> writeWebdavPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _writeConfigUpdates({kWebdavPassword: null});
      return;
    }
    await _writeConfigUpdates({kWebdavPassword: password});
  }

  Future<void> writeLocalDir(String? localDir) async {
    if (localDir == null || localDir.isEmpty) {
      await _writeConfigUpdates({kLocalDir: null});
      return;
    }
    await _writeConfigUpdates({kLocalDir: localDir});
  }

  Future<SyncConfig?> loadConfiguredSync() async {
    final all = await _loadConfigMap();
    if (all.isEmpty) return null;
    return _parseConfiguredSync(all);
  }

  Future<SyncConfig?> loadConfiguredSyncIfAutoEnabled() async {
    final all = await _loadConfigMap();
    if (all.isEmpty) return null;
    final auto = all[kAutoEnabled];
    if (auto != null && auto != '1') return null;
    return _parseConfiguredSync(all);
  }

  SyncConfig? _parseConfiguredSync(Map<String, String> all) {
    if (all.isEmpty) return null;

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

      try {
        await _storage.write(key: key, value: legacy);
        await _storage.delete(
          key: key,
          mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
        );
      } catch (_) {
        // Best-effort migration.
      }

      return legacy;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<String, String>> _loadConfigMap() async {
    final raw = await _safeRead(_kConfigBlobKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, String>{};
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is String) {
          result[key] = value;
          continue;
        }
        if (value == null) continue;
        result[key] = value.toString();
      }
      return result;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeConfigMap(Map<String, String> config) async {
    if (config.isEmpty) {
      await _safeDelete(_kConfigBlobKey);
      return;
    }
    await _safeWrite(_kConfigBlobKey, jsonEncode(config));
  }

  Future<void> _writeConfigUpdates(Map<String, String?> updates) async {
    final config = await _loadConfigMap();
    var changed = false;
    for (final entry in updates.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null || value.isEmpty) {
        changed = config.remove(key) != null || changed;
        continue;
      }
      if (config[key] != value) {
        config[key] = value;
        changed = true;
      }
    }
    if (!changed) return;
    await _writeConfigMap(config);
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
      // Fall through and try legacy storage below.
    }

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

  Future<void> clearAll() async {
    for (final key in _knownKeys) {
      await _safeDelete(key);
    }
  }
}
