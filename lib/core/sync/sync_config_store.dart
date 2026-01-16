import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_engine.dart';

final class SyncConfigStore {
  SyncConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _createDefaultSecureStorage();

  final FlutterSecureStorage _storage;

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
        mOptions: MacOsOptions(useDataProtectionKeyChain: false),
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
    final syncKey = await readSyncKey();
    if (syncKey == null || syncKey.length != 32) return null;

    final remoteRoot = (await readRemoteRoot())?.trim();
    if (remoteRoot == null || remoteRoot.isEmpty) return null;

    final backendType = await readBackendType();
    switch (backendType) {
      case SyncBackendType.webdav:
        final baseUrl = (await readWebdavBaseUrl())?.trim();
        if (baseUrl == null || baseUrl.isEmpty) return null;
        final username = (await readWebdavUsername())?.trim();
        final password = await readWebdavPassword();
        return SyncConfig.webdav(
          syncKey: syncKey,
          remoteRoot: remoteRoot,
          baseUrl: baseUrl,
          username: username == null || username.isEmpty ? null : username,
          password: password == null || password.isEmpty ? null : password,
        );
      case SyncBackendType.localDir:
        final localDir = (await readLocalDir())?.trim();
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
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
