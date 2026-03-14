import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage warns before marking incomplete checklist done',
      (tester) async {
    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.tap(find.byKey(const ValueKey('todo_detail_set_status_done')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo_detail_incomplete_checklist_dialog')),
        findsOneWidget);
    expect(backend.updateCalls, 0);

    await tester.tap(
        find.byKey(const ValueKey('todo_detail_incomplete_checklist_confirm')));
    await tester.pumpAndSettle();

    expect(backend.updateCalls, 1);
    expect(backend.lastNewStatus, 'done');
  });
}

final class _Backend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  int updateCalls = 0;
  String? lastNewStatus;

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
  Future<List<TodoActivity>> listTodoActivities(
          Uint8List key, String todoId) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ];

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistSuggestion>[];

  @override
  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) async {
    updateCalls += 1;
    lastNewStatus = newStatus;
    return Todo(
      id: todoId,
      title: 'Task',
      status: newStatus,
      createdAtMs: 0,
      updatedAtMs: 1,
    );
  }
}
