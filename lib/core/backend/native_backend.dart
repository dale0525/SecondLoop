import 'dart:convert';

import 'package:flutter/foundation.dart';
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
        mOptions: MacOsOptions(useDataProtectionKeyChain: false),
      );
    }
    return const FlutterSecureStorage();
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
    final value = await _secureStorage.read(key: _kAutoUnlockEnabled);
    if (value == null) return true;
    return value == '1';
  }

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {
    await _secureStorage.write(key: _kAutoUnlockEnabled, value: enabled ? '1' : '0');
    if (!enabled) {
      await clearSavedSessionKey();
    }
  }

  @override
  Future<Uint8List?> loadSavedSessionKey() async {
    final autoUnlockEnabled = await readAutoUnlockEnabled();
    if (!autoUnlockEnabled) return null;

    final b64 = await _secureStorage.read(key: _kSessionKeyB64);
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
    await _secureStorage.write(key: _kSessionKeyB64, value: base64Encode(key));
    await _secureStorage.write(key: _kAutoUnlockEnabled, value: '1');
  }

  @override
  Future<void> clearSavedSessionKey() async {
    await _secureStorage.delete(key: _kSessionKeyB64);
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
}
