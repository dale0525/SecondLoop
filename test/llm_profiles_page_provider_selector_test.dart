import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/llm_profiles_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('LLM profiles page shows provider selector', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _EmptyLlmProfilesBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const LlmProfilesPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('llm_provider_type')), findsOneWidget);
  });

  testWidgets('Switching provider updates default model name', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _EmptyLlmProfilesBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const LlmProfilesPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final openAiModelField = tester.widget<TextField>(
      find.byKey(const ValueKey('llm_model_name')),
    );
    expect(openAiModelField.controller?.text, 'gpt-4o-mini');

    final openAiBaseUrlField = tester.widget<TextField>(
      find.byKey(const ValueKey('llm_base_url')),
    );
    expect(openAiBaseUrlField.controller?.text, 'https://api.openai.com/v1');

    await tester.tap(find.byKey(const ValueKey('llm_provider_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini').last);
    await tester.pumpAndSettle();

    final geminiModelField = tester.widget<TextField>(
      find.byKey(const ValueKey('llm_model_name')),
    );
    expect(geminiModelField.controller?.text, 'gemini-1.5-flash');

    final geminiBaseUrlField = tester.widget<TextField>(
      find.byKey(const ValueKey('llm_base_url')),
    );
    expect(
      geminiBaseUrlField.controller?.text,
      'https://generativelanguage.googleapis.com/v1beta',
    );

    await tester.tap(find.byKey(const ValueKey('llm_provider_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic').last);
    await tester.pumpAndSettle();

    final anthropicBaseUrlField = tester.widget<TextField>(
      find.byKey(const ValueKey('llm_base_url')),
    );
    expect(
        anthropicBaseUrlField.controller?.text, 'https://api.anthropic.com/v1');
  });

  testWidgets('OpenAI-only filter hides incompatible active profiles',
      (tester) async {
    final backend = _EmptyLlmProfilesBackend(
      initialProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'openai-1',
          name: 'OpenAI',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'gpt-4o-mini',
          isActive: false,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        LlmProfile(
          id: 'gemini-1',
          name: 'Gemini',
          providerType: 'gemini-compatible',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          modelName: 'gemini-1.5-flash',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const LlmProfilesPage(
                providerFilter: LlmProfilesProviderFilter.openAiCompatibleOnly,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('openai-compatible'), findsOneWidget);
    expect(find.textContaining('gemini-compatible'), findsNothing);
  });

  testWidgets('Media BYOK mode limits provider selector to OpenAI-compatible',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _EmptyLlmProfilesBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const LlmProfilesPage(
                providerFilter: LlmProfilesProviderFilter.openAiCompatibleOnly,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('llm_provider_type')),
    );

    final dropdownButton = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('llm_provider_type')),
        matching: find.byWidgetPredicate(
          (widget) => widget is DropdownButton<String>,
        ),
      ),
    );

    expect(
      dropdownButton.items?.map((item) => item.value).toList(growable: false),
      const <String>['openai-compatible'],
    );
    expect(selector.onChanged, isNull);
  });
}

final class _EmptyLlmProfilesBackend extends AppBackend {
  _EmptyLlmProfilesBackend({
    this.initialProfiles = const <LlmProfile>[],
  });

  final List<LlmProfile> initialProfiles;

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
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async =>
      throw UnimplementedError();

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
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key,
          {int batchLimit = 256}) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(
          Uint8List key, String modelName) async =>
      false;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      initialProfiles;

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
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async =>
      throw UnimplementedError();

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
