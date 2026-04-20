import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_config_store_platform_stub.dart'
    if (dart.library.io) 'sync_config_store_platform_io.dart';
import '../storage/secure_blob_store.dart';
import 'sync_config_migrator.dart';
import 'sync_diagnostics.dart';
import 'sync_engine.dart';
import 'sync_key_manager.dart';
import 'sync_secret_store.dart';

final class SyncConfigStore {
  SyncConfigStore({
    FlutterSecureStorage? storage,
    SyncSecretStore? secretStore,
    String? scopeKey,
    bool allowSecureStoreMigrationInTestEnvironment = false,
    String managedVaultDefaultBaseUrl = const String.fromEnvironment(
      'SECONDLOOP_MANAGED_VAULT_BASE_URL',
      defaultValue: '',
    ),
  })  : _unusedLegacySecureStorage = storage,
        _scopeKey = _normalizeScopeKey(scopeKey),
        _allowSecureStoreMigrationInTestEnvironment =
            allowSecureStoreMigrationInTestEnvironment,
        _secretStore = secretStore ??
            SyncSecretStore(scopeKey: _normalizeScopeKey(scopeKey)),
        _managedVaultDefaultBaseUrl = managedVaultDefaultBaseUrl;

  final FlutterSecureStorage? _unusedLegacySecureStorage;
  final String? _scopeKey;
  final bool _allowSecureStoreMigrationInTestEnvironment;
  final SyncSecretStore _secretStore;
  final String _managedVaultDefaultBaseUrl;
  late final SyncConfigMigrator _migrator =
      SyncConfigMigrator(secretStore: _secretStore);

  static const _kPrefsBlobKey = SyncConfigMigrator.publicPrefsBlobKey;
  static const _kLegacyPrefsBlobKey = SyncConfigMigrator.legacyPrefsBlobKey;
  static const prefsBlobKeyForTest = _kPrefsBlobKey;
  static const legacyPrefsBlobKeyForTest = _kLegacyPrefsBlobKey;
  static const syncSecretStoreVersionPrefsKeyForTest =
      SyncConfigMigrator.secretStoreVersionPrefsKey;
  static final ValueNotifier<int> _changeCounter = ValueNotifier<int>(0);

  Future<void> _tail = Future<void>.value();
  Future<SharedPreferences>? _prefsFuture;

  bool _loaded = false;
  String? _lastRaw;
  Map<String, String> _cache = <String, String>{};

  Listenable get changes => _changeCounter;

  static const kBackendType = 'sync_backend_type'; // webdav | localdir
  static const kAutoEnabled = 'sync_auto_enabled'; // 1 | 0
  static const kAutoWifiOnly = 'sync_auto_wifi_only'; // 1 | 0
  static const kChatThumbnailsWifiOnly =
      'sync_chat_thumbnails_wifi_only'; // 1 | 0
  static const kMediaDownloadsWifiOnly = kChatThumbnailsWifiOnly; // 1 | 0
  static const kLocalDir = 'sync_localdir_path';

  static const kWebdavBaseUrl = 'sync_webdav_base_url';
  static const kWebdavUsername = 'sync_webdav_username';
  static const kWebdavPassword = SyncConfigMigrator.webdavPasswordKey;
  static const kRemoteRoot = 'sync_webdav_remote_root';
  static const kSyncKeyB64 = SyncConfigMigrator.syncKeyB64Key;
  static const kManagedVaultBaseUrl = 'sync_managed_vault_base_url';

  static const kCloudMediaBackupEnabled = 'cloud_media_backup_enabled'; // 1|0
  static const kCloudMediaBackupWifiOnly =
      'cloud_media_backup_wifi_only'; // 1|0
  static const _kCloudMediaBackupBackfillDonePrefix =
      'cloud_media_backup_backfill_done:';
  static const _kManagedVaultMediaUploadPendingPrefix =
      'managed_vault_media_upload_pending:';
  static const _kBackgroundSyncResultPrefix = 'sync_background_result:';
  static const _kBackgroundSyncBackoffPrefix = 'sync_background_backoff:';
  static const _kBackgroundSyncRepairRequiredPrefix =
      'sync_background_repair_required:';
  static const _kSyncRefreshV2Enabled = 'sync_refresh_v2_enabled'; // 1|0
  static const _kSyncBackgroundDiagV1Enabled =
      'sync_background_diag_v1_enabled'; // 1|0
  static const _kSyncBackoffV1Enabled = 'sync_backoff_v1_enabled'; // 1|0

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
    if (_scopeKey == null) {
      final cached = SyncKeyManager.readCachedSyncKey();
      if (cached != null && cached.length == 32) return cached;
    }

    final secret = await _secretStore.readSyncKey();
    if (secret != null && secret.length == 32) {
      if (_scopeKey == null) {
        SyncKeyManager.cacheSyncKey(secret);
      }
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
      if (_scopeKey == null) {
        SyncKeyManager.cacheSyncKey(legacy);
      }
    } else {
      if (_scopeKey == null) {
        SyncKeyManager.clearSyncKeyCache();
      }
    }
    await _writeConfigUpdates({kSyncKeyB64: null});
    return legacy;
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _secretStore.writeSyncKey(key);
    if (_scopeKey == null) {
      SyncKeyManager.cacheSyncKey(key);
    }
    await _writeConfigUpdates({kSyncKeyB64: null});
  }

  Future<void> clearSyncKey() async {
    await _secretStore.clearSyncKey();
    if (_scopeKey == null) {
      SyncKeyManager.clearSyncKeyCache();
    }
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

  Future<bool> readSyncRefreshV2Enabled() async {
    final v = (await _loadConfigMap())[_kSyncRefreshV2Enabled];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeSyncRefreshV2Enabled(bool enabled) async {
    await _writeConfigUpdates({_kSyncRefreshV2Enabled: enabled ? '1' : '0'});
  }

  Future<bool> readSyncBackgroundDiagV1Enabled() async {
    final v = (await _loadConfigMap())[_kSyncBackgroundDiagV1Enabled];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeSyncBackgroundDiagV1Enabled(bool enabled) async {
    await _writeConfigUpdates({
      _kSyncBackgroundDiagV1Enabled: enabled ? '1' : '0',
    });
  }

  Future<bool> readSyncBackoffV1Enabled() async {
    final v = (await _loadConfigMap())[_kSyncBackoffV1Enabled];
    if (v == null) return true;
    return v == '1';
  }

  Future<void> writeSyncBackoffV1Enabled(bool enabled) async {
    await _writeConfigUpdates({_kSyncBackoffV1Enabled: enabled ? '1' : '0'});
  }

  Future<bool> readCloudMediaBackupBackfillDone({
    required String scopeId,
  }) async {
    final key = _syncStateKey(_kCloudMediaBackupBackfillDonePrefix, scopeId);
    if (key == null) return false;
    final v = (await _loadConfigMap())[key];
    return v == '1';
  }

  Future<void> writeCloudMediaBackupBackfillDone({
    required String scopeId,
    required bool done,
  }) async {
    final key = _syncStateKey(_kCloudMediaBackupBackfillDonePrefix, scopeId);
    if (key == null) return;
    await _writeConfigUpdates({key: done ? '1' : null});
  }

  Future<bool> readManagedVaultMediaUploadPending({
    required String scopeId,
  }) async {
    final key = _syncStateKey(_kManagedVaultMediaUploadPendingPrefix, scopeId);
    if (key == null) return false;
    final raw = (await _loadConfigMap())[key];
    return raw == '1';
  }

  Future<void> writeManagedVaultMediaUploadPending({
    required String scopeId,
    required bool pending,
  }) async {
    final key = _syncStateKey(_kManagedVaultMediaUploadPendingPrefix, scopeId);
    if (key == null) return;
    await _writeConfigUpdates({key: pending ? '1' : null});
  }

  Future<SyncBackgroundResult?> readBackgroundSyncResult({
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final all = await _loadConfigMap();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      return _decodeBackgroundSyncResult(
        all[_backgroundSyncScopedKey(
          _kBackgroundSyncResultPrefix,
          backendType,
          scopeId: scopeId,
        )],
      );
    }
    return _readLatestBackgroundSyncValue(
      all,
      prefix: _kBackgroundSyncResultPrefix,
      backendType: backendType,
      decode: _decodeBackgroundSyncResult,
      sortValue: (value) => value.timestampMs,
    );
  }

  Future<void> writeBackgroundSyncResult(
    SyncBackgroundResult? result, {
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final key = _backgroundSyncScopedKey(
      _kBackgroundSyncResultPrefix,
      backendType,
      scopeId: scopeId,
    );
    if (result == null) {
      await _writeConfigUpdates({key: null});
      return;
    }
    await _writeConfigUpdates({key: jsonEncode(result.toJson())});
  }

  Future<SyncBackgroundBackoffState?> readBackgroundSyncBackoffState({
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final all = await _loadConfigMap();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      return _decodeBackgroundSyncBackoffState(
        all[_backgroundSyncScopedKey(
          _kBackgroundSyncBackoffPrefix,
          backendType,
          scopeId: scopeId,
        )],
      );
    }
    return _readLatestBackgroundSyncValue(
      all,
      prefix: _kBackgroundSyncBackoffPrefix,
      backendType: backendType,
      decode: _decodeBackgroundSyncBackoffState,
      sortValue: (value) => value.updatedAtMs,
    );
  }

  Future<void> writeBackgroundSyncBackoffState(
    SyncBackgroundBackoffState? state, {
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final key = _backgroundSyncScopedKey(
      _kBackgroundSyncBackoffPrefix,
      backendType,
      scopeId: scopeId,
    );
    if (state == null) {
      await _writeConfigUpdates({key: null});
      return;
    }
    await _writeConfigUpdates({key: jsonEncode(state.toJson())});
  }

  Future<bool> readBackgroundSyncRepairRequired({
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final all = await _loadConfigMap();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      return all[_backgroundSyncScopedKey(
            _kBackgroundSyncRepairRequiredPrefix,
            backendType,
            scopeId: scopeId,
          )] ==
          '1';
    }

    final legacyKey = _backgroundSyncLegacyKey(
      _kBackgroundSyncRepairRequiredPrefix,
      backendType,
    );
    final scopedPrefix = '$legacyKey:';
    if (all[legacyKey] == '1') return true;
    for (final entry in all.entries) {
      if (entry.key.startsWith(scopedPrefix) && entry.value == '1') {
        return true;
      }
    }
    return false;
  }

  Future<void> writeBackgroundSyncRepairRequired(
    bool required, {
    required SyncBackendType backendType,
    String? scopeId,
  }) async {
    final key = _backgroundSyncScopedKey(
      _kBackgroundSyncRepairRequiredPrefix,
      backendType,
      scopeId: scopeId,
    );
    await _writeConfigUpdates({key: required ? '1' : null});
  }

  String syncStateScopeId(SyncConfig config) {
    return syncStateScopeIdForFields(
      backendType: config.backendType,
      baseUrl: config.baseUrl,
      localDir: config.localDir,
      username: config.username,
      remoteRoot: config.remoteRoot,
      syncKey: config.syncKey,
    );
  }

  String syncStateScopeIdForFields({
    required SyncBackendType backendType,
    String? baseUrl,
    String? localDir,
    String? username,
    required String remoteRoot,
    Uint8List? syncKey,
  }) {
    final backend = switch (backendType) {
      SyncBackendType.webdav => 'webdav',
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
    };

    final raw = [
      backend,
      baseUrl?.trim() ?? '',
      localDir?.trim() ?? '',
      username?.trim() ?? '',
      remoteRoot.trim(),
      _syncKeyFingerprint(syncKey),
    ].join('|');
    return base64Url.encode(utf8.encode(raw));
  }

  static String _syncKeyFingerprint(Uint8List? syncKey) {
    if (syncKey == null || syncKey.isEmpty) return '';

    var hash = 0xcbf29ce484222325;
    for (final byte in syncKey) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _backendTypeToken(SyncBackendType backendType) {
    return switch (backendType) {
      SyncBackendType.webdav => 'webdav',
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
    };
  }

  String _backgroundSyncScopedKey(
    String prefix,
    SyncBackendType backendType, {
    String? scopeId,
  }) {
    final backendKey = _backgroundSyncLegacyKey(prefix, backendType);
    final stateKey = _syncStateKey('$backendKey:', scopeId);
    if (stateKey == null) {
      return backendKey;
    }
    return stateKey;
  }

  String _backgroundSyncLegacyKey(
    String prefix,
    SyncBackendType backendType,
  ) {
    return '$prefix${_backendTypeToken(backendType)}';
  }

  SyncBackgroundResult? _decodeBackgroundSyncResult(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SyncBackgroundResult.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  SyncBackgroundBackoffState? _decodeBackgroundSyncBackoffState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SyncBackgroundBackoffState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  T? _readLatestBackgroundSyncValue<T>(
    Map<String, String> all, {
    required String prefix,
    required SyncBackendType backendType,
    required T? Function(String? raw) decode,
    required int Function(T value) sortValue,
  }) {
    final legacyKey = _backgroundSyncLegacyKey(prefix, backendType);
    final scopedPrefix = '$legacyKey:';
    T? best;
    var bestSortValue = -0x7fffffffffffffff;

    void consider(String key) {
      final decoded = decode(all[key]);
      if (decoded == null) return;
      final candidateSortValue = sortValue(decoded);
      if (best == null || candidateSortValue > bestSortValue) {
        best = decoded;
        bestSortValue = candidateSortValue;
      }
    }

    consider(legacyKey);
    for (final key in all.keys) {
      if (key.startsWith(scopedPrefix)) {
        consider(key);
      }
    }
    return best;
  }

  String? _syncStateKey(String prefix, String? scopeId) {
    final normalizedScope = scopeId?.trim();
    if (normalizedScope == null || normalizedScope.isEmpty) {
      return null;
    }
    return '$prefix$normalizedScope';
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
      final hadState = _cache.isNotEmpty || _lastRaw != null;
      final prefs = await _prefs();
      await prefs.remove(_prefsBlobKey);
      await prefs.remove(_legacyPrefsBlobKey);
      await prefs.remove(_secretStoreVersionPrefsKey);
      await _secretStore.clearAll();
      if (_scopeKey == null) {
        SyncKeyManager.clearSyncKeyCache();
      }
      _lastRaw = null;
      _cache = <String, String>{};
      _loaded = true;
      if (hadState) {
        _notifyChanged();
      }
    });
  }

  String? _readRawConfigBlob(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsBlobKey);
    if (raw != null && raw.trim().isNotEmpty) return raw;
    final legacyRaw = prefs.getString(_legacyPrefsBlobKey);
    if (legacyRaw != null && legacyRaw.trim().isNotEmpty) return legacyRaw;
    return null;
  }

  Future<void> _reloadIfChanged() async {
    if (!_loaded) return;

    final prefs = await _prefs();
    final raw = _readRawConfigBlob(prefs);
    if (raw == _lastRaw) return;

    if (raw == null || raw.trim().isEmpty) {
      _lastRaw = null;
      _cache = <String, String>{};
      return;
    }

    _lastRaw = raw;
    _cache = _migrator.decodeRawConfigMap(raw);
    await _migrateSensitiveFieldsFromPublicCacheIfNeeded();
    final hasPublicBlob =
        prefs.getString(_prefsBlobKey)?.trim().isNotEmpty == true;
    final hasLegacyBlob =
        prefs.getString(_legacyPrefsBlobKey)?.trim().isNotEmpty == true;
    if (!hasPublicBlob && hasLegacyBlob) {
      await _persistCache();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final prefs = await _prefs();
    final raw = _readRawConfigBlob(prefs);
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
    _cache = _migrator.decodeRawConfigMap(raw);

    _loaded = true;
    await _migrateSensitiveFieldsFromPublicCacheIfNeeded();
    final hasPublicBlob =
        prefs.getString(_prefsBlobKey)?.trim().isNotEmpty == true;
    final hasLegacyBlob =
        prefs.getString(_legacyPrefsBlobKey)?.trim().isNotEmpty == true;
    if (!hasPublicBlob && hasLegacyBlob) {
      await _persistCache();
    }
  }

  Future<Map<String, String>> _tryMigrateFromSecureStore() async {
    if (syncConfigStoreIsFlutterTestEnvironment() &&
        !_allowSecureStoreMigrationInTestEnvironment) {
      return <String, String>{};
    }

    if (syncConfigStoreIsMacPlatform() &&
        !_allowSecureStoreMigrationInTestEnvironment) {
      return <String, String>{};
    }

    final storage = _unusedLegacySecureStorage ?? const FlutterSecureStorage();
    final scopedSecure = SecureBlobStore(
      storage: storage,
      scopeKey: _scopeKey,
    );

    Future<Map<String, String>> readSecure(SecureBlobStore secure) async {
      try {
        return await secure.readAll().timeout(const Duration(seconds: 1),
            onTimeout: () => <String, String>{});
      } catch (_) {
        return <String, String>{};
      }
    }

    var legacy = await readSecure(scopedSecure);
    var migratedFromUnscoped = false;
    SecureBlobStore? unscopedSecure;
    if (legacy.isEmpty && _scopeKey != null) {
      unscopedSecure = SecureBlobStore(storage: storage);
      legacy = await readSecure(unscopedSecure);
      migratedFromUnscoped = legacy.isNotEmpty;
    }

    final migrated = <String, String>{};
    for (final key in <String>[
      kBackendType,
      kAutoEnabled,
      kLocalDir,
      kManagedVaultBaseUrl,
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
    var migratedSecret = false;
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      await _secretStore.writeWebdavPassword(legacyPassword);
      migratedSecret = true;
    }

    final legacySyncKeyB64 = legacy[kSyncKeyB64];
    final legacyHadCredential =
        legacySyncKeyB64 != null && legacySyncKeyB64.isNotEmpty;
    if (legacySyncKeyB64 != null && legacySyncKeyB64.isNotEmpty) {
      try {
        final decoded = base64Decode(legacySyncKeyB64);
        if (decoded.length == 32) {
          final key = Uint8List.fromList(decoded);
          await _secretStore.writeSyncKey(key);
          if (_scopeKey == null) {
            SyncKeyManager.cacheSyncKey(key);
          }
          migratedSecret = true;
        }
      } catch (_) {
        // Ignore malformed legacy sync key.
      }
    }
    if (migratedSecret) {
      await _markSecretStoreVersion();
    }
    if (migratedFromUnscoped && (!legacyHadCredential || migratedSecret)) {
      await unscopedSecure?.clear();
    }
    return migrated;
  }

  Future<void> _migrateSensitiveFieldsFromPublicCacheIfNeeded() async {
    final migrationResult =
        await _migrator.migrateSensitiveFieldsFromPublicConfig(_cache);
    if (!migrationResult.movedSensitiveFields) {
      return;
    }

    _cache = migrationResult.publicConfig;
    await _markSecretStoreVersion();
    await _persistCache();
  }

  Future<void> _markSecretStoreVersion() async {
    final prefs = await _prefs();
    final current = prefs.getInt(_secretStoreVersionPrefsKey);
    if (current == SyncConfigMigrator.secretStoreVersion) return;
    await prefs.setInt(
      _secretStoreVersionPrefsKey,
      SyncConfigMigrator.secretStoreVersion,
    );
  }

  Future<void> _persistCache() async {
    final prefs = await _prefs();
    if (_cache.isEmpty) {
      await prefs.remove(_prefsBlobKey);
      await prefs.remove(_legacyPrefsBlobKey);
      _lastRaw = null;
      _notifyChanged();
      return;
    }
    final raw = jsonEncode(_cache);
    await prefs.setString(_prefsBlobKey, raw);
    await prefs.remove(_legacyPrefsBlobKey);
    _lastRaw = raw;
    _notifyChanged();
  }

  void _notifyChanged() {
    _changeCounter.value++;
  }

  String get _prefsBlobKey => _scopedKey(_kPrefsBlobKey);

  String get _legacyPrefsBlobKey => _scopedKey(_kLegacyPrefsBlobKey);

  String get _secretStoreVersionPrefsKey =>
      _scopedKey(SyncConfigMigrator.secretStoreVersionPrefsKey);

  String _scopedKey(String key) {
    final scopeKey = _scopeKey;
    if (scopeKey == null) return key;
    return '$key::$scopeKey';
  }

  static String? _normalizeScopeKey(String? scopeKey) {
    final normalized = scopeKey?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }
}
