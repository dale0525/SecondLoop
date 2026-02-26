import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_blob_store.dart';
import 'sync_engine.dart';
import 'sync_key_manager.dart';
import 'sync_secret_store.dart';

final class SyncConfigStore {
  SyncConfigStore({
    FlutterSecureStorage? storage,
    SyncSecretStore? secretStore,
    String managedVaultDefaultBaseUrl = const String.fromEnvironment(
      'SECONDLOOP_MANAGED_VAULT_BASE_URL',
      defaultValue: '',
    ),
  })  : _unusedLegacySecureStorage = storage,
        _secretStore = secretStore ?? SyncSecretStore(),
        _managedVaultDefaultBaseUrl = managedVaultDefaultBaseUrl;

  final FlutterSecureStorage? _unusedLegacySecureStorage;
  final SyncSecretStore _secretStore;
  final String _managedVaultDefaultBaseUrl;

  static const _kPrefsBlobKey = 'sync_config_plain_json_v1';
  static const prefsBlobKeyForTest = _kPrefsBlobKey;

  Future<void> _tail = Future<void>.value();
  Future<SharedPreferences>? _prefsFuture;

  bool _loaded = false;
  String? _lastRaw;
  Map<String, String> _cache = <String, String>{};

  static const kBackendType = 'sync_backend_type'; // webdav | localdir
  static const kAutoEnabled = 'sync_auto_enabled'; // 1 | 0
  static const kAutoWifiOnly = 'sync_auto_wifi_only'; // 1 | 0
  static const kChatThumbnailsWifiOnly =
      'sync_chat_thumbnails_wifi_only'; // 1 | 0
  static const kMediaDownloadsWifiOnly = kChatThumbnailsWifiOnly; // 1 | 0
  static const kLocalDir = 'sync_localdir_path';

  static const kWebdavBaseUrl = 'sync_webdav_base_url';
  static const kWebdavUsername = 'sync_webdav_username';
  static const kWebdavPassword = 'sync_webdav_password';
  static const kRemoteRoot = 'sync_webdav_remote_root';
  static const kSyncKeyB64 = 'sync_webdav_sync_key_b64';
  static const kManagedVaultBaseUrl = 'sync_managed_vault_base_url';

  static const kCloudMediaBackupEnabled = 'cloud_media_backup_enabled'; // 1|0
  static const kCloudMediaBackupWifiOnly =
      'cloud_media_backup_wifi_only'; // 1|0
  static const _kCloudMediaBackupBackfillDonePrefix =
      'cloud_media_backup_backfill_done:';

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

  Future<bool> readAutoWifiOnly() async {
    final v = (await _loadConfigMap())[kAutoWifiOnly];
    if (v == null) return false;
    return v == '1';
  }

  Future<void> writeAutoWifiOnly(bool enabled) async {
    await _writeConfigUpdates({kAutoWifiOnly: enabled ? '1' : '0'});
  }

  Future<bool> readMediaDownloadsWifiOnly() async {
    final v = (await _loadConfigMap())[kMediaDownloadsWifiOnly];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeMediaDownloadsWifiOnly(bool enabled) async {
    await _writeConfigUpdates({kMediaDownloadsWifiOnly: enabled ? '1' : '0'});
  }

  Future<bool> readChatThumbnailsWifiOnly() {
    return readMediaDownloadsWifiOnly();
  }

  Future<void> writeChatThumbnailsWifiOnly(bool enabled) {
    return writeMediaDownloadsWifiOnly(enabled);
  }

  Future<SyncBackendType> readBackendType() async {
    final v = (await _loadConfigMap())[kBackendType];
    return switch (v) {
      'localdir' => SyncBackendType.localDir,
      'managedvault' => SyncBackendType.managedVault,
      _ => SyncBackendType.webdav,
    };
  }

  Future<void> writeBackendType(SyncBackendType type) async {
    final v = switch (type) {
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
      SyncBackendType.webdav => 'webdav',
    };
    await _writeConfigUpdates({kBackendType: v});
  }

  Future<Uint8List?> readSyncKey() async {
    final cached = SyncKeyManager.readCachedSyncKey();
    if (cached != null && cached.length == 32) return cached;

    final secret = await _secretStore.readSyncKey();
    if (secret != null && secret.length == 32) {
      SyncKeyManager.cacheSyncKey(secret);
      return secret;
    }

    final b64 = (await _loadConfigMap())[kSyncKeyB64];
    if (b64 == null || b64.isEmpty) return null;
    Uint8List? legacy;
    try {
      final decoded = base64Decode(b64);
      if (decoded.length == 32) {
        legacy = Uint8List.fromList(decoded);
      }
    } catch (_) {
      legacy = null;
    }

    if (legacy != null) {
      await _secretStore.writeSyncKey(legacy);
      SyncKeyManager.cacheSyncKey(legacy);
    } else {
      SyncKeyManager.clearSyncKeyCache();
    }
    await _writeConfigUpdates({kSyncKeyB64: null});
    return legacy;
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _secretStore.writeSyncKey(key);
    SyncKeyManager.cacheSyncKey(key);
    await _writeConfigUpdates({kSyncKeyB64: null});
  }

  Future<String?> readWebdavBaseUrl() async =>
      (await _loadConfigMap())[kWebdavBaseUrl];
  Future<String?> readManagedVaultBaseUrl() async =>
      (await _loadConfigMap())[kManagedVaultBaseUrl];
  Future<String?> resolveManagedVaultBaseUrl() async {
    final v = (await _loadConfigMap())[kManagedVaultBaseUrl]?.trim();
    if (v != null && v.isNotEmpty) return v;
    final fallback = _managedVaultDefaultBaseUrl.trim();
    return fallback.isEmpty ? null : fallback;
  }

  Future<String?> readWebdavUsername() async =>
      (await _loadConfigMap())[kWebdavUsername];
  Future<String?> readWebdavPassword() async {
    final secret = await _secretStore.readWebdavPassword();
    if (secret != null && secret.isNotEmpty) return secret;

    final legacy = (await _loadConfigMap())[kWebdavPassword];
    if (legacy == null || legacy.isEmpty) return null;
    await _secretStore.writeWebdavPassword(legacy);
    await _writeConfigUpdates({kWebdavPassword: null});
    return legacy;
  }

  Future<String?> readRecoveryEnvelopeJson() async {
    return _secretStore.readRecoveryEnvelopeJson();
  }

  Future<String?> readRemoteRoot() async =>
      (await _loadConfigMap())[kRemoteRoot];
  Future<String?> readLocalDir() async => (await _loadConfigMap())[kLocalDir];

  Future<void> writeWebdavBaseUrl(String baseUrl) async =>
      _writeConfigUpdates({kWebdavBaseUrl: baseUrl});
  Future<void> writeManagedVaultBaseUrl(String baseUrl) async =>
      _writeConfigUpdates({kManagedVaultBaseUrl: baseUrl});
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
    await _secretStore.writeWebdavPassword(password);
    await _writeConfigUpdates({kWebdavPassword: null});
  }

  Future<void> writeRecoveryEnvelopeJson(String? envelopeJson) async {
    await _secretStore.writeRecoveryEnvelopeJson(envelopeJson);
  }

  Future<void> writeLocalDir(String? localDir) async {
    if (localDir == null || localDir.isEmpty) {
      await _writeConfigUpdates({kLocalDir: null});
      return;
    }
    await _writeConfigUpdates({kLocalDir: localDir});
  }

  Future<bool> readCloudMediaBackupEnabled() async {
    final v = (await _loadConfigMap())[kCloudMediaBackupEnabled];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeCloudMediaBackupEnabled(bool enabled) async {
    await _writeConfigUpdates({kCloudMediaBackupEnabled: enabled ? '1' : '0'});
  }

  Future<bool> readCloudMediaBackupWifiOnly() async {
    final v = (await _loadConfigMap())[kCloudMediaBackupWifiOnly];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeCloudMediaBackupWifiOnly(bool enabled) async {
    await _writeConfigUpdates({kCloudMediaBackupWifiOnly: enabled ? '1' : '0'});
  }

  Future<bool> readCloudMediaBackupBackfillDone({
    required String scopeId,
  }) async {
    final trimmedScope = scopeId.trim();
    if (trimmedScope.isEmpty) return false;
    final key = '$_kCloudMediaBackupBackfillDonePrefix$trimmedScope';
    final v = (await _loadConfigMap())[key];
    return v == '1';
  }

  Future<void> writeCloudMediaBackupBackfillDone({
    required String scopeId,
    required bool done,
  }) async {
    final trimmedScope = scopeId.trim();
    if (trimmedScope.isEmpty) return;
    final key = '$_kCloudMediaBackupBackfillDonePrefix$trimmedScope';
    await _writeConfigUpdates({key: done ? '1' : null});
  }

  String cloudMediaBackupBackfillScopeId(SyncConfig config) {
    final backend = switch (config.backendType) {
      SyncBackendType.webdav => 'webdav',
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
    };

    final raw = [
      backend,
      config.baseUrl?.trim() ?? '',
      config.localDir?.trim() ?? '',
      config.remoteRoot.trim(),
    ].join('|');
    return base64Url.encode(utf8.encode(raw));
  }

  Future<SyncConfig?> loadConfiguredSync() async {
    final all = await _loadConfigMap();
    if (all.isEmpty) return null;
    final syncKey = await readSyncKey();
    final webdavPassword = await readWebdavPassword();
    return _parseConfiguredSync(
      all,
      syncKey: syncKey,
      webdavPassword: webdavPassword,
    );
  }

  Future<SyncConfig?> loadConfiguredSyncIfAutoEnabled() async {
    final all = await _loadConfigMap();
    if (all.isEmpty) return null;
    final auto = all[kAutoEnabled];
    if (auto != null && auto != '1') return null;
    final syncKey = await readSyncKey();
    final webdavPassword = await readWebdavPassword();
    return _parseConfiguredSync(
      all,
      syncKey: syncKey,
      webdavPassword: webdavPassword,
    );
  }

  SyncConfig? _parseConfiguredSync(
    Map<String, String> all, {
    required Uint8List? syncKey,
    required String? webdavPassword,
  }) {
    if (all.isEmpty) return null;
    if (syncKey == null || syncKey.length != 32) return null;

    final remoteRoot = all[kRemoteRoot]?.trim();
    if (remoteRoot == null || remoteRoot.isEmpty) return null;

    final backendType = switch (all[kBackendType]) {
      'localdir' => SyncBackendType.localDir,
      'managedvault' => SyncBackendType.managedVault,
      _ => SyncBackendType.webdav,
    };
    switch (backendType) {
      case SyncBackendType.webdav:
        final baseUrl = all[kWebdavBaseUrl]?.trim();
        if (baseUrl == null || baseUrl.isEmpty) return null;
        final username = all[kWebdavUsername]?.trim();
        return SyncConfig.webdav(
          syncKey: syncKey,
          remoteRoot: remoteRoot,
          baseUrl: baseUrl,
          username: username == null || username.isEmpty ? null : username,
          password: webdavPassword == null || webdavPassword.isEmpty
              ? null
              : webdavPassword,
        );
      case SyncBackendType.localDir:
        final localDir = all[kLocalDir]?.trim();
        if (localDir == null || localDir.isEmpty) return null;
        return SyncConfig.localDir(
          syncKey: syncKey,
          remoteRoot: remoteRoot,
          localDir: localDir,
        );
      case SyncBackendType.managedVault:
        final baseUrl =
            (all[kManagedVaultBaseUrl] ?? _managedVaultDefaultBaseUrl).trim();
        if (baseUrl.isEmpty) return null;
        return SyncConfig.managedVault(
          syncKey: syncKey,
          vaultId: remoteRoot,
          baseUrl: baseUrl,
        );
    }
  }

  Future<Map<String, String>> _loadConfigMap() async {
    return _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      await _migrateSensitiveFieldsFromPublicCacheIfNeeded();
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
      await _secretStore.clearAll();
      SyncKeyManager.clearSyncKeyCache();
      _lastRaw = null;
      _cache = <String, String>{};
      _loaded = true;
    });
  }

  Future<void> _reloadIfChanged() async {
    if (!_loaded) return;

    final prefs = await _prefs();
    final raw = prefs.getString(_kPrefsBlobKey);
    if (raw == _lastRaw) return;

    if (raw == null || raw.trim().isEmpty) {
      _lastRaw = null;
      _cache = <String, String>{};
      return;
    }

    _lastRaw = raw;
    _cache = _decodeRawConfigMap(raw);
    await _migrateSensitiveFieldsFromPublicCacheIfNeeded();
  }

  Map<String, String> _decodeRawConfigMap(String raw) {
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

      _lastRaw = null;
      _cache = <String, String>{};
      _loaded = true;
      return;
    }

    _lastRaw = raw;
    _cache = _decodeRawConfigMap(raw);

    _loaded = true;
    await _migrateSensitiveFieldsFromPublicCacheIfNeeded();
  }

  Future<Map<String, String>> _tryMigrateFromSecureStore() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return <String, String>{};
    }

    final isMac =
        Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS;
    if (isMac) {
      return <String, String>{};
    }

    final secure = SecureBlobStore(
      storage: _unusedLegacySecureStorage ?? const FlutterSecureStorage(),
    );

    Map<String, String> legacy;
    try {
      legacy = await secure.readAll().timeout(const Duration(seconds: 1),
          onTimeout: () => <String, String>{});
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
      kRemoteRoot,
    ]) {
      final v = legacy[key];
      if (v != null && v.isNotEmpty) {
        migrated[key] = v;
      }
    }

    final legacyPassword = legacy[kWebdavPassword];
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      await _secretStore.writeWebdavPassword(legacyPassword);
    }

    final legacySyncKeyB64 = legacy[kSyncKeyB64];
    if (legacySyncKeyB64 != null && legacySyncKeyB64.isNotEmpty) {
      try {
        final decoded = base64Decode(legacySyncKeyB64);
        if (decoded.length == 32) {
          final key = Uint8List.fromList(decoded);
          await _secretStore.writeSyncKey(key);
          SyncKeyManager.cacheSyncKey(key);
        }
      } catch (_) {
        // Ignore malformed legacy sync key.
      }
    }
    return migrated;
  }

  Future<void> _migrateSensitiveFieldsFromPublicCacheIfNeeded() async {
    final legacyPassword = _cache[kWebdavPassword];
    final legacySyncKeyB64 = _cache[kSyncKeyB64];
    if ((legacyPassword == null || legacyPassword.isEmpty) &&
        (legacySyncKeyB64 == null || legacySyncKeyB64.isEmpty)) {
      return;
    }

    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      await _secretStore.writeWebdavPassword(legacyPassword);
    }
    if (legacySyncKeyB64 != null && legacySyncKeyB64.isNotEmpty) {
      try {
        final decoded = base64Decode(legacySyncKeyB64);
        if (decoded.length == 32) {
          final key = Uint8List.fromList(decoded);
          await _secretStore.writeSyncKey(key);
          SyncKeyManager.cacheSyncKey(key);
        }
      } catch (_) {
        // Ignore malformed legacy sync key.
      }
    }

    _cache.remove(kWebdavPassword);
    _cache.remove(kSyncKeyB64);
    await _persistCache();
  }

  Future<void> _persistCache() async {
    final prefs = await _prefs();
    if (_cache.isEmpty) {
      await prefs.remove(_kPrefsBlobKey);
      _lastRaw = null;
      return;
    }
    final raw = jsonEncode(_cache);
    await prefs.setString(_kPrefsBlobKey, raw);
    _lastRaw = raw;
  }
}
