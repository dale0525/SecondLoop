import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_blob_store.dart';
import 'sync_engine.dart';

final class SyncConfigStore {
  SyncConfigStore({
    FlutterSecureStorage? storage,
  }) : _unusedLegacySecureStorage = storage;

  final FlutterSecureStorage? _unusedLegacySecureStorage;

  static const _kPrefsBlobKey = 'sync_config_plain_json_v1';

  Future<void> _tail = Future<void>.value();
  Future<SharedPreferences>? _prefsFuture;

  bool _loaded = false;
  Map<String, String> _cache = <String, String>{};

  static const kBackendType = 'sync_backend_type'; // webdav | localdir
  static const kAutoEnabled = 'sync_auto_enabled'; // 1 | 0
  static const kLocalDir = 'sync_localdir_path';

  static const kWebdavBaseUrl = 'sync_webdav_base_url';
  static const kWebdavUsername = 'sync_webdav_username';
  static const kWebdavPassword = 'sync_webdav_password';
  static const kRemoteRoot = 'sync_webdav_remote_root';
  static const kSyncKeyB64 = 'sync_webdav_sync_key_b64';

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}).catchError((_) {});
    return next;
  }

  Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
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

  Future<Map<String, String>> _loadConfigMap() async {
    return _serial(() async {
      await _ensureLoaded();
      return Map<String, String>.from(_cache);
    });
  }

  Future<void> _writeConfigUpdates(Map<String, String?> updates) async {
    await _serial(() async {
      await _ensureLoaded();

      var changed = false;
      for (final entry in updates.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value == null || value.isEmpty) {
          changed = _cache.remove(key) != null || changed;
          continue;
        }
        if (_cache[key] != value) {
          _cache[key] = value;
          changed = true;
        }
      }

      if (!changed) return;
      await _persistCache();
    });
  }

  Future<void> clearAll() async {
    await _serial(() async {
      final prefs = await _prefs();
      await prefs.remove(_kPrefsBlobKey);
      _cache = <String, String>{};
      _loaded = true;
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final prefs = await _prefs();
    final raw = prefs.getString(_kPrefsBlobKey);
    if (raw == null || raw.trim().isEmpty) {
      final migrated = await _tryMigrateFromSecureStore();
      if (migrated.isNotEmpty) {
        _cache = migrated;
        _loaded = true;
        await _persistCache();
        return;
      }

      _cache = <String, String>{};
      _loaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _cache = <String, String>{};
        _loaded = true;
        return;
      }

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
      _cache = result;
    } catch (_) {
      _cache = <String, String>{};
    }

    _loaded = true;
  }

  Future<Map<String, String>> _tryMigrateFromSecureStore() async {
    final isMac = Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS;
    final allowKeychainRead = !isMac;
    final secure = SecureBlobStore(storage: _unusedLegacySecureStorage);
    if (!allowKeychainRead && !secure.isLoaded) {
      return <String, String>{};
    }

    Map<String, String> legacy;
    try {
      legacy = await secure.readAll();
    } catch (_) {
      return <String, String>{};
    }

    final migrated = <String, String>{};
    for (final key in <String>[
      kBackendType,
      kAutoEnabled,
      kLocalDir,
      kWebdavBaseUrl,
      kWebdavUsername,
      kWebdavPassword,
      kRemoteRoot,
      kSyncKeyB64,
    ]) {
      final v = legacy[key];
      if (v != null && v.isNotEmpty) {
        migrated[key] = v;
      }
    }
    return migrated;
  }

  Future<void> _persistCache() async {
    final prefs = await _prefs();
    if (_cache.isEmpty) {
      await prefs.remove(_kPrefsBlobKey);
      return;
    }
    await prefs.setString(_kPrefsBlobKey, jsonEncode(_cache));
  }
}
