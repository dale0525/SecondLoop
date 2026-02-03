import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Todo agenda banner shows scheduled todos due today/overdue',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);
    final yesterdayNoonLocal = todayNoonLocal.subtract(const Duration(days: 1));

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: '分析对标账户的直播内容',
          dueAtMs: todayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'todo:overdue',
          title: '买狗狗的口粮',
          dueAtMs: yesterdayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm2',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                splashFactory: InkRipple.splashFactory,
              ),
              home: const ChatPage(
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
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_agenda_banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo_agenda_preview_list')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_todo:today')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_todo:overdue')),
      findsOneWidget,
    );

    expect(find.text('分析对标账户的直播内容'), findsOneWidget);
    expect(find.text('买狗狗的口粮'), findsOneWidget);

    expect(find.byKey(const ValueKey('todo_agenda_view_all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('todo_agenda_view_all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_agenda_page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_agenda_item_todo:today')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_agenda_item_todo:overdue')),
      findsOneWidget,
    );
    expect(find.text('分析对标账户的直播内容'), findsOneWidget);
    expect(find.text('买狗狗的口粮'), findsOneWidget);
  });

  testWidgets('Todo agenda banner auto-collapses after 10 seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: todayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                splashFactory: InkRipple.splashFactory,
              ),
              home: const ChatPage(
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
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_list')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 9));
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_list')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_list')),
      findsNothing,
    );
  });

  testWidgets('Todo agenda banner collapses when returning to chat page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: todayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                splashFactory: InkRipple.splashFactory,
              ),
              home: const ChatPage(
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
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_list')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('todo_agenda_view_all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_agenda_page')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_agenda_preview_list')),
      findsNothing,
    );
  });

  testWidgets('Todo agenda banner shows upcoming todos when none due today',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final tomorrowNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12)
            .add(const Duration(days: 1));

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:tomorrow',
          title: '跟进客户会议',
          dueAtMs: tomorrowNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                splashFactory: InkRipple.splashFactory,
              ),
              home: const ChatPage(
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
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_agenda_banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_agenda_preview_todo:tomorrow')),
      findsOneWidget,
    );
    expect(find.text('跟进客户会议'), findsOneWidget);

    expect(find.byKey(const ValueKey('todo_agenda_view_all')), findsOneWidget);
  });
}

final class _AgendaBackend extends AppBackend {
  _AgendaBackend({List<Todo>? todos})
      : _todosById = {
          for (final todo in todos ?? const <Todo>[]) todo.id: todo,
        };

  final Map<String, Todo> _todosById;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async =>
      Uint8List.fromList(List<int>.filled(32, 1));

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
      Conversation(id: 'c1', title: title, createdAtMs: 0, updatedAtMs: 0);

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
      Message(
        id: 'm1',
        conversationId: conversationId,
        role: role,
        content: content,
        createdAtMs: 0,
        isMemory: true,
      );

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {}

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {}

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      _todosById.values.toList(growable: false);

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
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todosById[id]?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todosById[id] = todo;
    return todo;
  }

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
      Uint8List.fromList(List<int>.filled(32, 1));

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
