import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('task hub page groups todos by urgency sections', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'due',
          title: 'Due today',
          dueAtMs: DateTime(now.year, now.month, now.day, 14)
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'review',
          title: 'Needs review',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: 0,
          nextReviewAtMs: now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'unscheduled',
          title: 'Backlog idea',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'done',
          title: 'Finished task',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
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
            child: const MaterialApp(home: TaskHubPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_scheduled')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_section_unscheduled_merged')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_section_unscheduled_review')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_section_unscheduled_plain')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_done')),
        findsOneWidget);

    expect(
        find.byKey(const ValueKey('task_hub_page_item_due')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_review')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_unscheduled')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_done')), findsOneWidget);
  });

  testWidgets('task hub page loads done todos in batches on demand',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _TaskHubBackend(
      todos: <Todo>[
        for (var i = 0; i < 25; i++)
          Todo(
            id: 'done-$i',
            title: 'Done $i',
            dueAtMs: null,
            status: 'done',
            sourceEntryId: null,
            createdAtMs: i,
            updatedAtMs: i,
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
            child: const MaterialApp(home: TaskHubPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_item_done-0')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_done_load_more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_page_item_done-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      findsNothing,
    );
  });

  testWidgets('task hub page quick action today updates backend',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'todo-1',
          title: 'Task 1',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
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
            child: const MaterialApp(home: TaskHubPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo-1_today')));
    await tester.pumpAndSettle();

    expect(backend.current('todo-1').status, 'open');
    expect(backend.current('todo-1').dueAtMs, isNotNull);
  });

  testWidgets('task hub page done section exposes reopen quick action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'done-1',
          title: 'Finished task',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
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
            child: const MaterialApp(home: TaskHubPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_quick_done-1_reopen')),
    );
    await tester.pumpAndSettle();

    expect(backend.current('done-1').status, 'open');
  });

  testWidgets('task hub page task row opens todo detail page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'todo-open',
          title: 'Open detail',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
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
            child: const MaterialApp(home: TaskHubPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_item_todo-open')));
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailPage), findsOneWidget);
  });
}

final class _TaskHubBackend extends TestAppBackend {
  _TaskHubBackend({required List<Todo> todos})
      : _todosById = {for (final todo in todos) todo.id: todo};

  final Map<String, Todo> _todosById;

  Todo current(String id) => _todosById[id]!;

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
    final updated = Todo(
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
    _todosById[id] = updated;
    return updated;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todosById[todoId]!;
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
}
