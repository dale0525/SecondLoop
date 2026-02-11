import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/llm_profiles_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Configure AI entry opens unified intelligence settings',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});

      final backend = _NoLlmProfileBackend();
      final subscriptions =
          _FakeSubscriptionStatusController(SubscriptionStatus.unknown);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SubscriptionScope(
                controller: subscriptions,
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: const ChatPage(
                    conversation: Conversation(
                      id: 'main_stream',
                      title: 'Main Stream',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        'hello?',
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat_configure_ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_ask_ai')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chat_configure_ai')));
      await tester.pumpAndSettle();

      expect(find.byType(AiSettingsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
          findsOneWidget);

      expect(
        find.byKey(const ValueKey('ai_settings_open_cloud_account')),
        findsNothing,
      );

      await tester
          .tap(find.byKey(const ValueKey('ai_settings_open_llm_profiles')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.byType(LlmProfilesPage), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final class _NoLlmProfileBackend extends AppBackend {
  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      const <Conversation>[];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      const Conversation(
        id: 'main_stream',
        title: 'Main Stream',
        createdAtMs: 0,
        updatedAtMs: 0,
      );

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      const <Message>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(
          Uint8List key, String messageId, String content) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(false);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 2));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  set status(SubscriptionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }
}
