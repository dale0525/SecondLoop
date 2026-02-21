import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Send message triggers todo update prompt when RAG matches',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend(
      todos: const [
        Todo(
          id: 't1',
          title: '下午 2 点有客户来拜访，需要接待',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      similarTodoThreads: const [
        TodoThreadMatch(todoId: 't1', distance: 0.2),
      ],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), 'met the client');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    for (var i = 0;
        i < 50 && find.text('Update a task?').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(backend.searchCalls, greaterThanOrEqualTo(1));
    expect(find.text('Update a task?'), findsOneWidget);
    expect(find.text('下午 2 点有客户来拜访，需要接待'), findsOneWidget);
  });

  testWidgets('Send long-form note does not auto-create todo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend(
      todos: const [],
      similarTodoThreads: const [],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    const longFormNote =
        'tomorrow 3pm submit report\nContext: include invoice details, budget summary, and follow-up notes for audit.';

    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), longFormNote);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(backend.upsertedTodoIds, isEmpty);
  });

  testWidgets('Send long single-line note does not auto-create todo',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend(
      todos: const [],
      similarTodoThreads: const [],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    const longSingleLineNote =
        'tomorrow 3pm submit report with budget details, invoice checklist, stakeholders updates, and audit notes for weekly review';

    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), longSingleLineNote);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(backend.upsertedTodoIds, isEmpty);
  });
}

Widget _wrapChat({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const ChatPage(
            conversation: Conversation(
              id: 'loop_home',
              title: 'Loop',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _Backend extends AppBackend {
  _Backend({
    required List<Todo> todos,
    required List<TodoThreadMatch> similarTodoThreads,
  })  : _todos = List<Todo>.from(todos),
        _similar = List<TodoThreadMatch>.from(similarTodoThreads);

  final List<Todo> _todos;
  final List<TodoThreadMatch> _similar;
  final List<Message> _messages = [];
  final List<String> upsertedTodoIds = <String>[];
  int searchCalls = 0;

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
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    upsertedTodoIds.add(id);
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos.removeWhere((item) => item.id == id);
    _todos.add(todo);
    return todo;
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      () {
        searchCalls += 1;
        return List<TodoThreadMatch>.from(_similar);
      }();

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
