import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('task hub shows focus scheduled decide and done sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    final backend = _TaskHubBackend(
      todos: <Todo>[
        const Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'scheduled',
          title: 'Draft roadmap',
          dueAtMs: tomorrowNoon.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'review',
          title: 'Review follow-up',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: 0,
          nextReviewAtMs: now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'done',
          title: 'Shipped',
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
      checklistProgress: const <TodoChecklistProgress>[
        TodoChecklistProgress(todoId: 'focus', totalCount: 2, doneCount: 1),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_focus')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_scheduled')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_focus')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task_hub_checklist_progress_focus')),
      findsOneWidget,
    );
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_scheduled')),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_hub_page_section_done')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_done')), findsOneWidget);
  });

  testWidgets('task hub quick action failure shows error snackbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: <Todo>[
        const Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
      failUpsert: true,
    );

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('task_hub_page_quick_focus_start'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('unfinished tasks show active priority controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'urgent-important',
          title: 'Critical launch task',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(
          'task_hub_page_priority_urgent-important_urgency_active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(
          'task_hub_page_priority_urgent-important_importance_active')),
      findsOneWidget,
    );
  });

  testWidgets(
      'task hub keeps remaining focus tasks visible below primary focus',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final overdueBase = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(hours: 1));
    final backend = _TaskHubBackend(
      todos: <Todo>[
        for (var i = 0; i < 4; i++)
          Todo(
            id: 'focus-$i',
            title: 'Focus task $i',
            dueAtMs: overdueBase
                .subtract(Duration(hours: i))
                .toUtc()
                .millisecondsSinceEpoch,
            status: 'open',
            sourceEntryId: null,
            createdAtMs: i,
            updatedAtMs: 100 - i,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: null,
          ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_page_section_focus')),
        findsOneWidget);
    expect(find.text('Focus task 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_focus-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_focus-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_focus-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_item_focus-3')),
        findsOneWidget);
  });

  testWidgets('task hub loads done todos in batches on demand', (tester) async {
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

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_page_done_load_more')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_done-0')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_done_load_more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_page_item_done-0')),
        findsOneWidget);
  });
}

Widget _wrap(AppBackend backend) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const TaskHubPage(),
        ),
      ),
    ),
  );
}

final class _TaskHubBackend extends TestAppBackend {
  _TaskHubBackend({
    required List<Todo> todos,
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    this.failUpsert = false,
  })  : _todos = {for (final todo in todos) todo.id: todo},
        _checklistProgress =
            List<TodoChecklistProgress>.from(checklistProgress);

  final Map<String, Todo> _todos;
  final List<TodoChecklistProgress> _checklistProgress;
  final bool failUpsert;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      _todos.values.toList(growable: false);

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async {
    return List<TodoChecklistProgress>.from(_checklistProgress);
  }

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
    if (failUpsert) {
      throw StateError('apply failed');
    }
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todos[id]?.createdAtMs ?? 0,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos[id] = updated;
    return updated;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todos[todoId]!;
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
    _todos[todoId] = updated;
    return updated;
  }
}
