import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

int _dueReviewAtMsForToday() {
  final nowLocal = DateTime.now();
  final startOfTodayLocal =
      DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  return startOfTodayLocal.toUtc().millisecondsSinceEpoch;
}

void main() {
  testWidgets('task hub done quick action notifies sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final dueReviewAtMs = _dueReviewAtMsForToday();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: dueReviewAtMs,
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
              const MaterialApp(home: TaskHubPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_done')));
    await tester.pumpAndSettle();

    expect(backend.setTodoStatusCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
  });

  testWidgets('task hub later quick action notifies sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final dueReviewAtMs = _dueReviewAtMsForToday();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: dueReviewAtMs,
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
              const MaterialApp(home: TaskHubPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_later')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pumpAndSettle();

    expect(backend.upsertTodoCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
    expect(find.text('review this'), findsWidgets);
  });

  testWidgets(
      'task hub quick action snackbar auto dismisses with accessible navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final dueReviewAtMs = _dueReviewAtMsForToday();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: dueReviewAtMs,
        ),
      ],
    );

    await tester.pumpWidget(
      SyncEngineScope(
        engine: SyncEngine(
          syncRunner: _NoopSyncRunner(),
          loadConfig: () async => null,
          pullOnStart: false,
        ),
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(accessibleNavigation: true),
                  child: child!,
                ),
                home: const TaskHubPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_later')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'task hub quick action snackbar does not linger after leaving page',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final dueReviewAtMs = _dueReviewAtMsForToday();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review this',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: dueReviewAtMs,
        ),
      ],
    );

    await tester.pumpWidget(
      SyncEngineScope(
        engine: SyncEngine(
          syncRunner: _NoopSyncRunner(),
          loadConfig: () async => null,
          pullOnStart: false,
        ),
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Home')),
                    body: Center(
                      child: ElevatedButton(
                        key: const ValueKey('open_task_hub_page'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TaskHubPage(),
                            ),
                          );
                        },
                        child: const Text('Open task hub'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_task_hub_page')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_later')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _TaskHubBackend implements AppBackend {
  _TaskHubBackend({required List<Todo> todos})
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
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

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
