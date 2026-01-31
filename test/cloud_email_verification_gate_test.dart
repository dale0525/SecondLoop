import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Cloud account shows resend verification when email is unverified',
      (tester) async {
    final cloudAuth = _FakeCloudAuthController(
      idToken: 'test-id-token',
      uid: 'uid_1',
      emailVerified: false,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: const CloudAccountPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signed in as test@example.com'), findsOneWidget);
    expect(find.textContaining('uid_1'), findsNothing);

    expect(find.byKey(const ValueKey('cloud_resend_verification')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud_resend_verification')));
    await tester.pumpAndSettle();

    expect(cloudAuth.sendEmailVerificationCalls, 1);
  });

  testWidgets(
      'Ask AI shows verify-email prompt when cloud returns email_not_verified',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'embeddings_data_consent_v1': false,
    });

    final backend = _EmailNotVerifiedBackend();
    final cloudAuth = _FakeCloudAuthController(
      idToken: 'test-id-token',
      uid: 'uid_1',
      emailVerified: false,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'gpt-test',
              ),
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

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('askAiStreamCloudGateway'));
    expect(backend.calls, isNot(contains('askAiStream')));

    expect(find.byKey(const ValueKey('ask_ai_email_not_verified_snack')),
        findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsNothing);
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({
    required this.idToken,
    required this.uid,
    required this.emailVerified,
  });

  final String idToken;

  @override
  final String? uid;

  @override
  final bool? emailVerified;

  @override
  String? get email => 'test@example.com';

  int sendEmailVerificationCalls = 0;

  @override
  Future<String?> getIdToken() async => idToken;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {
    sendEmailVerificationCalls += 1;
  }

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

final class _EmailNotVerifiedBackend extends AppBackend {
  final List<String> calls = <String>[];

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
  Future<List<Message>> listMessages(Uint8List key, String conversationId) =>
      Future<List<Message>>.value(const <Message>[]);

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
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
    String? conversationId,
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
      const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'OpenAI',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'gpt-4o-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];

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
  }) {
    calls.add('askAiStream');
    return Stream<String>.fromIterable(const ['byok']);
  }

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
  }) {
    calls.add('askAiStreamCloudGateway');
    return Stream<String>.error(
      Exception(
        'cloud-gateway request failed: HTTP 403 {"error":"email_not_verified"}',
      ),
    );
  }

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
