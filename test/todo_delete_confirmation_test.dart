import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Todo delete requires confirmation', (tester) async {
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

    final backend = _Backend(todo: todo);

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

    await tester.tap(find.byKey(const ValueKey('todo_detail_delete')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(backend.setTodoStatusCalls, 0);
  });

  testWidgets('Todo delete notifies sync engine', (tester) async {
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

    final backend = _Backend(todo: todo);

    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester.pumpWidget(
      SyncEngineScope(
        engine: engine,
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(home: TodoDetailPage(initialTodo: todo)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_detail_delete')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_delete_confirm')));
    await tester.pumpAndSettle();

    expect(backend.deleteTodoCalls, 1);
    expect(changes, 1);
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _Backend implements AppBackend {
  _Backend({required this.todo});

  final Todo todo;
  int setTodoStatusCalls = 0;
  int deleteTodoCalls = 0;

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    return Todo(
      id: todoId,
      title: todo.title,
      dueAtMs: todo.dueAtMs,
      status: newStatus,
      sourceEntryId: todo.sourceEntryId,
      createdAtMs: todo.createdAtMs,
      updatedAtMs: PlatformInt64Util.from(
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
      reviewStage: todo.reviewStage,
      nextReviewAtMs: todo.nextReviewAtMs,
      lastReviewAtMs: todo.lastReviewAtMs,
    );
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    deleteTodoCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
