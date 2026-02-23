import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Long press message -> link to todo appends note',
      (tester) async {
    final backend = _Backend(
      messages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task A',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    await tester.tap(find.text('Task A'));
    await tester.pumpAndSettle();

    expect(backend.noteLinks, [
      (todoId: 't1', content: 'hello', sourceMessageId: 'm1'),
    ]);
  });

  testWidgets('Todo link sheet supports searching', (tester) async {
    final backend = _Backend(
      messages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task A',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't2',
          title: 'Task B',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_note_link_search')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('todo_note_link_search')),
      'B',
    );
    await tester.pumpAndSettle();

    expect(find.text('Task A'), findsNothing);
    expect(find.text('Task B'), findsOneWidget);

    await tester.tap(find.text('Task B'));
    await tester.pumpAndSettle();

    expect(backend.noteLinks.last, (
      todoId: 't2',
      content: 'hello',
      sourceMessageId: 'm1',
    ));
  });
}

Widget _wrapChat({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
      ),
      home: AppBackendScope(
        backend: backend,
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
  );
}

final class _Backend extends AppBackend {
  _Backend({required List<Message> messages, required List<Todo> todos})
      : _messages = List<Message>.from(messages),
        _todos = List<Todo>.from(todos);

  final List<Message> _messages;
  final List<Todo> _todos;

  final List<({String todoId, String content, String sourceMessageId})>
      noteLinks = [];

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
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
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
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(
          Uint8List key, String messageId, String content) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    noteLinks.add(
      (
        todoId: todoId,
        content: content,
        sourceMessageId: sourceMessageId ?? '',
      ),
    );
    return TodoActivity(
      id: 'activity_1',
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: sourceMessageId,
      createdAtMs: 0,
    );
  }

  @override
  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) async {}

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
  Future<String> getActiveEmbeddingModelName(Uint8List key) async => '';

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
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 2));

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
