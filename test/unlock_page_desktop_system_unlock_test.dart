import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/lock/unlock_page.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets(
      'UnlockPage (desktop): defaults to system unlock and uses saved session key',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({
        'app_lock_enabled_v1': true,
      });

      final backend = _SavedKeyBackend();
      Uint8List? unlockedKey;

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: MaterialApp(
            home: UnlockPage(
              onUnlocked: (key) => unlockedKey = key,
              authenticateBiometrics: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Use system unlock'), findsOneWidget);

      await tester.tap(find.text('Use system unlock'));
      await tester.pumpAndSettle();

      expect(unlockedKey, isNotNull);
      expect(unlockedKey, orderedEquals(backend.savedKey));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final class _SavedKeyBackend implements AppBackend {
  final Uint8List savedKey = Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => false;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => Uint8List.fromList(savedKey);

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> unlockWithPassword(String password) =>
      throw UnimplementedError();

  @override
  Future<List<Conversation>> listConversations(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<Conversation> createConversation(Uint8List key, String title) =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) =>
      throw UnimplementedError();

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      throw UnimplementedError();

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key, {int limit = 32}) =>
      throw UnimplementedError();

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(Uint8List key, String query,
          {int topK = 10}) =>
      throw UnimplementedError();

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key, {int batchLimit = 256}) =>
      throw UnimplementedError();

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) =>
      throw UnimplementedError();

  @override
  Stream<String> askAiStream(Uint8List key, String conversationId,
          {required String question,
          int topK = 10,
          bool thisThreadOnly = false}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavTestConnection(
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPush(Uint8List key, Uint8List syncKey,
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPull(Uint8List key, Uint8List syncKey,
          {required String baseUrl,
          String? username,
          String? password,
          required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirTestConnection(
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPush(Uint8List key, Uint8List syncKey,
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPull(Uint8List key, Uint8List syncKey,
          {required String localDir, required String remoteRoot}) =>
      throw UnimplementedError();
}
