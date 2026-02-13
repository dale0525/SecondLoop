import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_page.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Todo agenda uses Delete (not Deleted) tooltip', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: _FakeBackend(todos: [todo]),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: TodoAgendaPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_agenda_item_t1')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('todo_agenda_item_t1'))),
      isA<InkWell>(),
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byTooltip('Deleted'), findsNothing);
  });

  testWidgets('Todo agenda can set status to done directly', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    final backend = _FakeBackend(todos: [todo]);

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: TodoAgendaPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusButton =
        find.byKey(const ValueKey('todo_agenda_set_status_t1_done'));
    expect(statusButton, findsOneWidget);
    expect(tester.widget(statusButton), isA<OutlinedButton>());

    await tester.tap(statusButton);
    await tester.pumpAndSettle();

    expect(backend.lastScopedStatusTodoId, 't1');
    expect(backend.lastScopedStatusNewStatus, 'done');
    expect(backend.lastScopedStatusScope, TodoRecurrenceEditScope.thisOnly);
    expect(backend.lastSetTodoStatusTodoId, isNull);
  });

  testWidgets('Todo detail can set status to done directly', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    final backend = _FakeBackend(todos: [todo]);

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(home: TodoDetailPage(initialTodo: todo)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final doneButton =
        find.byKey(const ValueKey('todo_detail_set_status_done'));
    expect(doneButton, findsOneWidget);
    expect(tester.widget(doneButton), isA<OutlinedButton>());

    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(backend.lastScopedStatusTodoId, 't1');
    expect(backend.lastScopedStatusNewStatus, 'done');
    expect(backend.lastScopedStatusScope, TodoRecurrenceEditScope.thisOnly);
    expect(backend.lastSetTodoStatusTodoId, isNull);
  });

  testWidgets('Todo agenda recurring non-done status supports scope selection',
      (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    final backend = _FakeBackend(
      todos: [todo],
      recurrenceTodoIds: const {'t1'},
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: TodoAgendaPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inProgressButton =
        find.byKey(const ValueKey('todo_agenda_set_status_t1_in_progress'));
    expect(inProgressButton, findsOneWidget);

    await tester.tap(inProgressButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_recurrence_scope_this_only')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('todo_recurrence_scope_this_and_future')),
    );
    await tester.pumpAndSettle();

    expect(backend.lastScopedStatusTodoId, 't1');
    expect(backend.lastScopedStatusNewStatus, 'in_progress');
    expect(
      backend.lastScopedStatusScope,
      TodoRecurrenceEditScope.thisAndFuture,
    );
    expect(backend.lastSetTodoStatusTodoId, isNull);
  });

  testWidgets('Todo detail recurring non-done status supports scope selection',
      (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    final backend = _FakeBackend(
      todos: [todo],
      recurrenceTodoIds: const {'t1'},
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(home: TodoDetailPage(initialTodo: todo)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inProgressButton =
        find.byKey(const ValueKey('todo_detail_set_status_in_progress'));
    expect(inProgressButton, findsOneWidget);

    await tester.tap(inProgressButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_recurrence_scope_whole_series')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('todo_recurrence_scope_whole_series')),
    );
    await tester.pumpAndSettle();

    expect(backend.lastScopedStatusTodoId, 't1');
    expect(backend.lastScopedStatusNewStatus, 'in_progress');
    expect(
      backend.lastScopedStatusScope,
      TodoRecurrenceEditScope.wholeSeries,
    );
    expect(backend.lastSetTodoStatusTodoId, isNull);
  });

  testWidgets('Todo detail uses Delete (not Deleted) tooltip', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Test todo',
      dueAtMs: PlatformInt64Util.from(1),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(1),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: _FakeBackend(todos: const []),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(home: TodoDetailPage(initialTodo: todo)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_detail_composer')), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byTooltip('Deleted'), findsNothing);
  });
}

final class _FakeBackend extends AppBackend {
  _FakeBackend({
    required this.todos,
    this.recurrenceTodoIds = const <String>{},
  });

  final List<Todo> todos;
  final Set<String> recurrenceTodoIds;
  final Map<String, Todo> _todosById = {};

  String? lastSetTodoStatusTodoId;
  String? lastSetTodoStatusNewStatus;
  String? lastScopedStatusTodoId;
  String? lastScopedStatusNewStatus;
  TodoRecurrenceEditScope? lastScopedStatusScope;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => false;

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
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    if (_todosById.isEmpty && todos.isNotEmpty) {
      _todosById.addAll({for (final todo in todos) todo.id: todo});
    }
    return _todosById.values.toList(growable: false);
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    lastSetTodoStatusTodoId = todoId;
    lastSetTodoStatusNewStatus = newStatus;

    final existing = _todosById[todoId];
    final updated = Todo(
      id: todoId,
      title: existing?.title ?? 'Test todo',
      dueAtMs: existing?.dueAtMs,
      status: newStatus,
      sourceEntryId: existing?.sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
      reviewStage: existing?.reviewStage,
      nextReviewAtMs: existing?.nextReviewAtMs,
      lastReviewAtMs: existing?.lastReviewAtMs,
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) async {
    Todo? existing = _todosById[todoId];
    if (existing == null) {
      for (final todo in todos) {
        if (todo.id == todoId) {
          existing = todo;
          break;
        }
      }
    }

    lastScopedStatusTodoId = todoId;
    lastScopedStatusNewStatus = newStatus;
    lastScopedStatusScope = scope;

    final updated = Todo(
      id: todoId,
      title: existing?.title ?? 'Test todo',
      dueAtMs: existing?.dueAtMs,
      status: newStatus,
      sourceEntryId: existing?.sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? PlatformInt64Util.from(1),
      updatedAtMs: PlatformInt64Util.from(
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
      reviewStage: existing?.reviewStage,
      nextReviewAtMs: existing?.nextReviewAtMs,
      lastReviewAtMs: existing?.lastReviewAtMs,
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async {
    if (recurrenceTodoIds.contains(todoId)) {
      return '{"freq":"daily","interval":1}';
    }
    return null;
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) =>
      throw UnimplementedError();

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
          Uint8List key, String query,
          {int topK = 10}) =>
      throw UnimplementedError();

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key, {int batchLimit = 256}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
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
  Future<void> deleteLlmProfile(Uint8List key, String profileId) =>
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
  Future<void> syncWebdavClearRemoteRoot(
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
  Future<void> syncLocaldirClearRemoteRoot(
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
