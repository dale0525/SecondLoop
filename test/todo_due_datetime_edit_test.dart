import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_page.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_button.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Todo agenda can edit due date/time', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Task',
      dueAtMs: DateTime(2026, 1, 31, 9, 0).toUtc().millisecondsSinceEpoch,
      status: 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
    final backend = _Backend(todos: [todo]);

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

    await tester.tap(find.byKey(const ValueKey('todo_agenda_due_t1')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('todo_agenda_due_picker_t1'));
    expect(dialog, findsOneWidget);

    final hourField = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<int>),
    );
    expect(hourField, findsNWidgets(2));

    await tester.tap(hourField.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();

    final buttons =
        find.descendant(of: dialog, matching: find.byType(SlButton));
    expect(buttons, findsNWidgets(2));
    await tester.ensureVisible(buttons.last);
    await tester.tap(buttons.last);
    await tester.pumpAndSettle();

    expect(
      backend.lastUpsertDueAtMs,
      DateTime(2026, 1, 31, 10, 0).toUtc().millisecondsSinceEpoch,
    );
  });

  testWidgets('Todo detail can edit due date/time', (tester) async {
    final todo = Todo(
      id: 't1',
      title: 'Task',
      dueAtMs: DateTime(2026, 1, 31, 9, 0).toUtc().millisecondsSinceEpoch,
      status: 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
    final backend = _Backend(todos: [todo]);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: TodoDetailPage(initialTodo: todo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_detail_due')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('todo_detail_due_picker'));
    expect(dialog, findsOneWidget);

    final hourField = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<int>),
    );
    expect(hourField, findsNWidgets(2));

    await tester.tap(hourField.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();

    final buttons =
        find.descendant(of: dialog, matching: find.byType(SlButton));
    expect(buttons, findsNWidgets(2));
    await tester.ensureVisible(buttons.last);
    await tester.tap(buttons.last);
    await tester.pumpAndSettle();

    expect(
      backend.lastUpsertDueAtMs,
      DateTime(2026, 1, 31, 10, 0).toUtc().millisecondsSinceEpoch,
    );
  });
}

final class _Backend extends AppBackend {
  _Backend({required List<Todo> todos})
      : _todosById = {
          for (final todo in todos) todo.id: todo,
        };

  final Map<String, Todo> _todosById;
  int? lastUpsertDueAtMs;

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
    lastUpsertDueAtMs = dueAtMs;
    final existing = _todosById[id];
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? 0,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todosById[id] = updated;
    return updated;
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
          Uint8List key, String todoId) async =>
      const <TodoActivity>[];

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) =>
      Future<int>.value(0);

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
          Uint8List key, String query,
          {int topK = 10}) =>
      Future<List<SimilarMessage>>.value(const <SimilarMessage>[]);

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key, {int batchLimit = 256}) =>
      Future<int>.value(0);

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
  }) =>
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
