import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../src/rust/db.dart';

abstract class AppBackend {
  Future<void> init();

  Future<bool> isMasterPasswordSet();

  Future<bool> readAutoUnlockEnabled();
  Future<void> persistAutoUnlockEnabled({required bool enabled});

  Future<Uint8List?> loadSavedSessionKey();
  Future<void> saveSessionKey(Uint8List key);
  Future<void> clearSavedSessionKey();

  Future<void> validateKey(Uint8List key);

  Future<Uint8List> initMasterPassword(String password);
  Future<Uint8List> unlockWithPassword(String password);

  Future<List<Conversation>> listConversations(Uint8List key);
  Future<Conversation> createConversation(Uint8List key, String title);

  Future<List<Message>> listMessages(Uint8List key, String conversationId);
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  });

  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  });

  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  });

  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  });

  Future<List<LlmProfile>> listLlmProfiles(Uint8List key);
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  });
  Future<void> setActiveLlmProfile(Uint8List key, String profileId);

  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  });

  Future<Uint8List> deriveSyncKey(String passphrase);

  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });

  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  });
}

class AppBackendScope extends InheritedWidget {
  const AppBackendScope({
    required this.backend,
    required super.child,
    super.key,
  });

  final AppBackend backend;

  static AppBackend of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppBackendScope>();
    assert(scope != null, 'No AppBackendScope found in widget tree');
    return scope!.backend;
  }

  @override
  bool updateShouldNotify(AppBackendScope oldWidget) => backend != oldWidget.backend;
}
