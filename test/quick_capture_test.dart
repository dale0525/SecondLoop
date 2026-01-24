import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/main.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_glass.dart';

void main() {
  testWidgets('Quick capture inserts into Main Stream and hides',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _UnlockedBackend();
    final controller = QuickCaptureController();

    await tester.pumpWidget(
        MyApp(backend: backend, quickCaptureController: controller));
    await tester.pumpAndSettle();

    controller.show();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quick_capture_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick_capture_ring')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quick_capture_ring')),
        matching: find.byKey(const ValueKey('quick_capture_input')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('quick_capture_input')),
        matching: find.byType(SlGlass),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('quick_capture_input')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('quick_capture_input')), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(backend.insertedMessages, hasLength(1));
    expect(backend.insertedMessages.single.conversationId, 'main_stream');
    expect(backend.insertedMessages.single.role, 'user');
    expect(backend.insertedMessages.single.content, 'hello');
    expect(find.byKey(const ValueKey('quick_capture_input')), findsNothing);
  });
}

final class _UnlockedBackend extends AppBackend {
  final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 1));

  final List<Conversation> _conversations = [
    const Conversation(
      id: 'main_stream',
      title: 'Main Stream',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  ];

  final List<Message> insertedMessages = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => _key;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async => _key;

  @override
  Future<Uint8List> unlockWithPassword(String password) async => _key;

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      List<Conversation>.from(_conversations);

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      _conversations.single;

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final conversation = Conversation(
        id: 'c_${_conversations.length + 1}',
        title: title,
        createdAtMs: 0,
        updatedAtMs: 0);
    _conversations.add(conversation);
    return conversation;
  }

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      const [];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final message = Message(
      id: 'm${insertedMessages.length + 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: 0,
    );
    insertedMessages.add(message);
    return message;
  }

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {}

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {}

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
      const <String>['secondloop-default-embed-v0'];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(modelName != 'secondloop-default-embed-v0');

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
  Future<Uint8List> deriveSyncKey(String passphrase) async => _key;

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
