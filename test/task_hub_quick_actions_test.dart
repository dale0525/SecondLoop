import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_action_layout.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
    int? reviewStage,
    int? nextReviewAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: null,
    );
  }

  testWidgets('unscheduled tasks recommend schedule as primary action',
      (tester) async {
    final entry = TaskPriorityEntry(
      todo: todo(id: 'u1', title: 'Backlog item', updatedAtMs: 10),
      band: TaskPriorityBand.decide,
      ruleScore: 10,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[
        TaskPriorityReasonKind.unscheduled
      ],
      suggestedAction: TaskPrioritySuggestionKind.schedule,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              buildTaskHubQuickActionLayout(context, entry: entry)
                  .$1
                  .first
                  .label,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Schedule'), findsOneWidget);
  });

  testWidgets(
      'future scheduled tasks do not expose a destructive primary schedule action',
      (tester) async {
    final dueLocal = DateTime(2026, 3, 20, 12);
    final entry = TaskPriorityEntry(
      todo: todo(
        id: 's1',
        title: 'Far future plan',
        updatedAtMs: 10,
        dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      ),
      band: TaskPriorityBand.scheduled,
      ruleScore: 10,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[
        TaskPriorityReasonKind.scheduledSoon,
      ],
      suggestedAction: TaskPrioritySuggestionKind.schedule,
      isFutureScheduled: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final layout =
                  buildTaskHubQuickActionLayout(context, entry: entry);
              return Text('primary:${layout.$1.length}');
            },
          ),
        ),
      ),
    );

    expect(find.text('primary:0'), findsOneWidget);
  });

  testWidgets('review due tasks recommend clarify as primary action',
      (tester) async {
    final entry = TaskPriorityEntry(
      todo: todo(id: 'r1', title: 'Review item', updatedAtMs: 10),
      band: TaskPriorityBand.decide,
      ruleScore: 10,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[TaskPriorityReasonKind.reviewDue],
      suggestedAction: TaskPrioritySuggestionKind.clarify,
      isReviewDue: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              buildTaskHubQuickActionLayout(context, entry: entry)
                  .$1
                  .first
                  .label,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Clarify'), findsOneWidget);
  });

  test('applies today and can undo to original todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't1', title: 'Task 1', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.today);
    expect(ticket, isNotNull);
    final afterToday = backend.current('t1');
    expect(afterToday.status, 'open');
    expect(afterToday.dueAtMs, isNotNull);
    expect(afterToday.reviewStage, isNull);
    expect(afterToday.nextReviewAtMs, isNull);

    await controller.undo(ticket!);
    final restored = backend.current('t1');
    expect(restored.status, initial.status);
    expect(restored.dueAtMs, initial.dueAtMs);
    expect(restored.reviewStage, initial.reviewStage);
    expect(restored.nextReviewAtMs, initial.nextReviewAtMs);
  });

  test('later action pushes todo back to inbox review queue', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't2', title: 'Task 2', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.later);
    expect(ticket, isNotNull);
    final updated = backend.current('t2');
    expect(updated.status, 'inbox');
    expect(updated.dueAtMs, isNull);
    expect(updated.reviewStage, 0);
    expect(updated.nextReviewAtMs, isNotNull);
  });

  test('done action sets status to done', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3', title: 'Task 3', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.current('t3').status, 'done');
  });

  test('done action is canceled when incomplete checklist is not confirmed',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3b', title: 'Task 3b', updatedAtMs: 10);
    final backend = _QuickActionBackend(
      initialTodos: [initial],
      checklistItemsByTodoId: <String, List<TodoChecklistItem>>{
        't3b': const <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'c1',
            todoId: 't3b',
            content: 'Still pending',
            sortOrder: 0,
            isDone: false,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      },
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      confirmDoneWithIncompleteChecklist: (_) async => false,
      checklistProgressByTodoId: const <String, TodoChecklistProgress>{
        't3b': TodoChecklistProgress(
          todoId: 't3b',
          totalCount: 1,
          doneCount: 0,
        ),
      },
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNull);
    expect(backend.current('t3b').status, 'open');
  });

  test('done action proceeds when incomplete checklist is confirmed', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3c', title: 'Task 3c', updatedAtMs: 10);
    final backend = _QuickActionBackend(
      initialTodos: [initial],
      checklistItemsByTodoId: <String, List<TodoChecklistItem>>{
        't3c': const <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'c1',
            todoId: 't3c',
            content: 'Still pending',
            sortOrder: 0,
            isDone: false,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      },
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      confirmDoneWithIncompleteChecklist: (_) async => true,
      checklistProgressByTodoId: const <String, TodoChecklistProgress>{
        't3c': TodoChecklistProgress(
          todoId: 't3c',
          totalCount: 1,
          doneCount: 0,
        ),
      },
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.current('t3c').status, 'done');
  });

  test('done action skips checklist fetch when cached progress is empty',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3d', title: 'Task 3d', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      checklistProgressByTodoId: const <String, TodoChecklistProgress>{},
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.checklistItemsQueryCount, 0);
  });

  test('done action fetches checklist when cached progress is incomplete',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3e', title: 'Task 3e', updatedAtMs: 10);
    final backend = _QuickActionBackend(
      initialTodos: [initial],
      checklistItemsByTodoId: <String, List<TodoChecklistItem>>{
        't3e': const <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'c1',
            todoId: 't3e',
            content: 'Still pending',
            sortOrder: 0,
            isDone: false,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      },
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      confirmDoneWithIncompleteChecklist: (_) async => false,
      checklistProgressByTodoId: const <String, TodoChecklistProgress>{
        't3e': TodoChecklistProgress(
          todoId: 't3e',
          totalCount: 1,
          doneCount: 0,
        ),
      },
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNull);
    expect(backend.checklistItemsQueryCount, 1);
  });

  test('start action moves todo to in_progress', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't4', title: 'Task 4', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);
    expect(ticket, isNotNull);
    expect(backend.current('t4').status, 'in_progress');
  });

  test('reopen action reopens done todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't5',
      title: 'Task 5',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.reopen);
    expect(ticket, isNotNull);
    expect(backend.current('t5').status, 'open');
  });

  test(
      'redo action with native backend enqueues followup generation for created todo',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't6n',
      title: 'Task 6 native',
      updatedAtMs: 10,
      status: 'done',
    );
    var todos = <Todo>[initial];
    var enqueueCount = 0;
    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListTodos: ({required String appDir, required List<int> key}) async =>
          List<Todo>.from(todos),
      dbUpsertTodo: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
      }) async {
        final updated = Todo(
          id: id,
          title: title,
          dueAtMs: dueAtMs,
          status: status,
          sourceEntryId: sourceEntryId,
          createdAtMs: 10,
          updatedAtMs: 11,
          reviewStage: reviewStage,
          nextReviewAtMs: nextReviewAtMs,
          lastReviewAtMs: lastReviewAtMs,
        );
        todos = [
          ...todos.where((item) => item.id != id),
          updated,
        ];
        return updated;
      },
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        enqueueCount += 1;
      },
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.redo);
    expect(ticket, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(enqueueCount, 1);
  });

  test('redo action creates a new open todo and can undo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't6',
      title: 'Task 6',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final beforeCount = backend.all().length;
    final ticket = await controller.apply(initial, TaskHubQuickAction.redo);
    expect(ticket, isNotNull);
    final afterCreate = backend.all();
    expect(afterCreate.length, beforeCount + 1);
    final created = afterCreate.firstWhere((todo) => todo.id != initial.id);
    expect(created.status, 'open');
    expect(created.dueAtMs, isNotNull);

    await controller.undo(ticket!);
    final restored = backend.current(created.id);
    expect(restored.status, 'dismissed');
  });
}

final class _QuickActionBackend extends AppBackend {
  _QuickActionBackend({
    List<Todo>? initialTodos,
    Map<String, List<TodoChecklistItem>>? checklistItemsByTodoId,
  })  : _checklistItemsByTodoId = Map<String, List<TodoChecklistItem>>.from(
          checklistItemsByTodoId ?? const <String, List<TodoChecklistItem>>{},
        ),
        _todosById = {
          for (final todo in initialTodos ?? const <Todo>[]) todo.id: todo,
        };

  final Map<String, Todo> _todosById;
  final Map<String, List<TodoChecklistItem>> _checklistItemsByTodoId;
  var checklistItemsQueryCount = 0;

  Todo current(String id) => _todosById[id]!;
  List<Todo> all() => _todosById.values.toList(growable: false);

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

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async {
    checklistItemsQueryCount += 1;
    return List<TodoChecklistItem>.from(
      _checklistItemsByTodoId[todoId] ?? const <TodoChecklistItem>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
