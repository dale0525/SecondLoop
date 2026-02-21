import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Todo update sheet shows enable-cloud button and opens consent dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'embeddings_data_consent_v1': false});

    final dueAtMs = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 30))
        .millisecondsSinceEpoch;
    final backend = _Backend(
      todos: [
        Todo(
          id: 't1',
          title: '下午 2 点接待客户',
          status: 'open',
          dueAtMs: dueAtMs,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final cloudAuth = _FakeCloudAuthController(idToken: 'test-id-token');
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          builder: (context, child) {
            return AppBackendScope(
              backend: backend,
              child: CloudAuthScope(
                controller: cloudAuth,
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.test',
                  modelName: 'gpt-test',
                ),
                child: SubscriptionScope(
                  controller: subscriptions,
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          home: const ChatPage(
            conversation: Conversation(
              id: 'loop_home',
              title: 'Loop',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'done');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();

    for (var i = 0;
        i < 100 && find.text('Update a task?').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Update a task?'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('todo_link_sheet_enable_cloud')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('todo_link_sheet_enable_cloud')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('embeddings_consent_dialog')),
        findsOneWidget);
  });
}

final class _Backend extends AppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;
  final List<Message> _messages = [];

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
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async =>
      List<Message>.from(_messages);

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final message = Message(
      id: 'm${_messages.length + 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: 0,
      isMemory: true,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <TodoThreadMatch>[];

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
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 2));

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      Future<void>.value();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      Future<void>.value();

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
          Uint8List key, String query,
          {int topK = 10}) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key,
          {int batchLimit = 256}) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async => '';

  @override
  Future<bool> setActiveEmbeddingModelName(
          Uint8List key, String modelName) async =>
      false;

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
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) =>
      Future<void>.value();

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) =>
      Future<void>.value();

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({required String idToken}) : _idToken = idToken;

  final String _idToken;

  @override
  String? get uid => 'uid-test';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => _idToken;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

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
