import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/review/review_queue_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('marking review todo done notifies sync engine', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _ReviewQueueBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: nowUtcMs + const Duration(hours: 1).inMilliseconds,
        ),
      ],
    );

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
              const MaterialApp(home: ReviewQueuePage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(backend.setTodoStatusCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
  });

  testWidgets('snoozing review todo notifies sync engine', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _ReviewQueueBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: nowUtcMs + const Duration(hours: 1).inMilliseconds,
        ),
      ],
    );

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
              const MaterialApp(home: ReviewQueuePage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.snooze_rounded));
    await tester.pumpAndSettle();

    expect(backend.upsertTodoCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _ReviewQueueBackend implements AppBackend {
  _ReviewQueueBackend({required List<Todo> todos})
      : _todosById = <String, Todo>{
          for (final todo in todos) todo.id: todo,
        };

  final Map<String, Todo> _todosById;
  int upsertTodoCalls = 0;
  int setTodoStatusCalls = 0;

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
    upsertTodoCalls += 1;
    final existing = _todosById[id];
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todosById[id] = todo;
    return todo;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) throw StateError('todo missing: $todoId');
    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: newStatus,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
