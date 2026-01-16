import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/core.dart' as rust_core;
import '../../src/rust/db.dart';
import '../../src/rust/frb_generated.dart';
import 'app_backend.dart';

class NativeAppBackend implements AppBackend {
  NativeAppBackend({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? _createDefaultSecureStorage();

  final FlutterSecureStorage _secureStorage;

  String? _appDir;

  static const _kAutoUnlockEnabled = 'auto_unlock_enabled';
  static const _kSessionKeyB64 = 'session_key_b64';

  static FlutterSecureStorage _createDefaultSecureStorage() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(),
      );
    }
    return const FlutterSecureStorage();
  }

  Future<String?> _readSecureString(String key) async {
    try {
      final v = await _secureStorage.read(key: key);
      if (v != null || defaultTargetPlatform != TargetPlatform.macOS) return v;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return null;

    try {
      final legacy = await _secureStorage.read(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
      if (legacy == null) return null;

      try {
        await _secureStorage.write(key: key, value: legacy);
        await _secureStorage.delete(
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

  Future<void> _writeSecureString(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _secureStorage.delete(
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
      await _secureStorage.write(
        key: key,
        value: value,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _deleteSecureString(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _secureStorage.delete(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
    } catch (_) {
      return;
    }
  }

  Future<String> _getAppDir() async {
    final cached = _appDir;
    if (cached != null) return cached;

    final dir = await getApplicationSupportDirectory();
    _appDir = dir.path;
    return _appDir!;
  }

  @override
  Future<void> init() async {
    await RustLib.init();
    await _getAppDir();
  }

  @override
  Future<bool> isMasterPasswordSet() async {
    final appDir = await _getAppDir();
    return rust_core.authIsInitialized(appDir: appDir);
  }

  @override
  Future<bool> readAutoUnlockEnabled() async {
    final value = await _readSecureString(_kAutoUnlockEnabled);
    if (value == null) return true;
    return value == '1';
  }

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {
    await _writeSecureString(_kAutoUnlockEnabled, enabled ? '1' : '0');
    if (!enabled) {
      await clearSavedSessionKey();
    }
  }

  @override
  Future<Uint8List?> loadSavedSessionKey() async {
    final autoUnlockEnabled = await readAutoUnlockEnabled();
    if (!autoUnlockEnabled) return null;

    final b64 = await _readSecureString(_kSessionKeyB64);
    if (b64 == null) return null;

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
    await _writeSecureString(_kSessionKeyB64, base64Encode(key));
    await _writeSecureString(_kAutoUnlockEnabled, '1');
  }

  @override
  Future<void> clearSavedSessionKey() async {
    await _deleteSecureString(_kSessionKeyB64);
  }

  @override
  Future<void> validateKey(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.authValidateKey(appDir: appDir, key: key);
  }

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    final appDir = await _getAppDir();
    return rust_core.authInitMasterPassword(appDir: appDir, password: password);
  }

  @override
  Future<Uint8List> unlockWithPassword(String password) async {
    final appDir = await _getAppDir();
    return rust_core.authUnlockWithPassword(appDir: appDir, password: password);
  }

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListConversations(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateMainStreamConversation(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateConversation(appDir: appDir, key: key, title: title);
  }

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessages(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
    );
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    final message = await rust_core.dbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: role,
      content: content,
    );

    await rust_core.dbProcessPendingMessageEmbeddings(
      appDir: appDir,
      key: key,
      limit: 32,
    );

    return message;
  }

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) async {
    final appDir = await _getAppDir();
    await rust_core.dbEditMessage(
      appDir: appDir,
      key: key,
      messageId: messageId,
      content: content,
    );
  }

  @override
  Future<void> setMessageDeleted(Uint8List key, String messageId, bool isDeleted) async {
    final appDir = await _getAppDir();
    await rust_core.dbSetMessageDeleted(
      appDir: appDir,
      key: key,
      messageId: messageId,
      isDeleted: isDeleted,
    );
  }

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbProcessPendingMessageEmbeddings(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessages(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
  }

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbRebuildMessageEmbeddings(
      appDir: appDir,
      key: key,
      batchLimit: batchLimit,
    );
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListLlmProfiles(appDir: appDir, key: key);
  }

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateLlmProfile(
      appDir: appDir,
      key: key,
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
      setActive: setActive,
    );
  }

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetActiveLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStream(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
    );
  }

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    return rust_core.syncDeriveKey(passphrase: passphrase);
  }

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    await rust_core.syncWebdavTestConnection(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncWebdavPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    return pushed.toInt();
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncWebdavPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    return pulled.toInt();
  }

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {
    await rust_core.syncLocaldirTestConnection(
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncLocaldirPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    return pushed.toInt();
  }

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncLocaldirPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    return pulled.toInt();
  }
}
