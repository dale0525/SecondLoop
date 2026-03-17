import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_action_layout.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';
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

  TaskPriorityEntry entry({
    required Todo todo,
    bool isUrgent = false,
    bool isImportant = false,
    TaskPriorityBand band = TaskPriorityBand.decide,
  }) {
    return TaskPriorityEntry(
      todo: todo,
      band: band,
      ruleScore: 10,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[
        TaskPriorityReasonKind.unscheduled
      ],
      suggestedAction: TaskPrioritySuggestionKind.schedule,
      isUrgent: isUrgent,
      isImportant: isImportant,
    );
  }

  testWidgets('backlog tasks prioritize increasing urgency', (tester) async {
    final candidate = entry(
      todo: todo(id: 'u1', title: 'Backlog item', updatedAtMs: 10),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              buildTaskHubQuickActionLayout(context, entry: candidate)
                  .$1
                  .first
                  .label,
            ),
          ),
        ),
      ),
    );

    expect(find.text('More urgent'), findsOneWidget);
  });

  testWidgets('urgent but not important tasks prioritize increasing importance',
      (tester) async {
    final candidate = entry(
      todo: todo(id: 'u2', title: 'Review item', updatedAtMs: 10),
      isUrgent: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              buildTaskHubQuickActionLayout(context, entry: candidate)
                  .$1
                  .first
                  .label,
            ),
          ),
        ),
      ),
    );

    expect(find.text('More important'), findsOneWidget);
  });

  testWidgets('urgent and important tasks prioritize finishing',
      (tester) async {
    final candidate = entry(
      todo: todo(id: 'u3', title: 'Ship it', updatedAtMs: 10),
      isUrgent: true,
      isImportant: true,
      band: TaskPriorityBand.focus,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              buildTaskHubQuickActionLayout(context, entry: candidate)
                  .$1
                  .first
                  .label,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Done'), findsOneWidget);
  });

  test('increase urgency moves backlog task to tomorrow schedule', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't1', title: 'Task 1', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket =
        await controller.apply(initial, TaskHubQuickAction.increaseUrgency);
    expect(ticket, isNotNull);
    final updated = backend.current('t1');
    expect(updated.status, 'open');
    expect(updated.dueAtMs, isNotNull);
    expect(updated.reviewStage, isNull);
    expect(updated.nextReviewAtMs, isNull);
  });

  test('increase urgency moves scheduled task to today', () async {
    SharedPreferences.setMockInitialValues({});

    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final initial = todo(
      id: 't2',
      title: 'Task 2',
      updatedAtMs: 10,
      dueAtMs: tomorrow.toUtc().millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket =
        await controller.apply(initial, TaskHubQuickAction.increaseUrgency);
    expect(ticket, isNotNull);
    final updated = backend.current('t2');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(updated.dueAtMs!, isUtc: true)
            .toLocal();
    final now = DateTime.now();
    expect(dueLocal.year, now.year);
    expect(dueLocal.month, now.month);
    expect(dueLocal.day, now.day);
  });

  test('decrease urgency moves urgent task to tomorrow', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't3',
      title: 'Task 3',
      updatedAtMs: 10,
      status: 'in_progress',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket =
        await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    expect(ticket, isNotNull);
    final updated = backend.current('t3');
    expect(updated.status, 'open');
    expect(updated.dueAtMs, isNotNull);
  });

  test('decrease urgency moves scheduled task back to inbox review queue',
      () async {
    SharedPreferences.setMockInitialValues({});

    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final initial = todo(
      id: 't4',
      title: 'Task 4',
      updatedAtMs: 10,
      dueAtMs: tomorrow.toUtc().millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket =
        await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    expect(ticket, isNotNull);
    final updated = backend.current('t4');
    expect(updated.status, 'inbox');
    expect(updated.dueAtMs, isNull);
    expect(updated.reviewStage, 0);
    expect(updated.nextReviewAtMs, isNotNull);
  });

  test('importance actions persist manual signal and support undo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't5', title: 'Task 5', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseImportance,
    );
    expect(ticket, isNotNull);
    expect((await signalStore.readForTodo('t5'))?.isImportant, isTrue);

    await controller.undo(ticket!);
    expect(await signalStore.readForTodo('t5'), isNull);
  });

  test(
      'decrease urgency clears persisted urgency override and undo restores it',
      () async {
    SharedPreferences.setMockInitialValues({});

    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final initial = todo(
      id: 't5b',
      title: 'Task 5b',
      updatedAtMs: 10,
      dueAtMs: tomorrow.toUtc().millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't5b',
      const TaskPriorityManualSignal(isUrgent: true),
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.decreaseUrgency,
    );
    expect(ticket, isNotNull);
    expect((await signalStore.readForTodo('t5b'))?.isUrgent, isFalse);

    await controller.undo(ticket!);
    expect((await signalStore.readForTodo('t5b'))?.isUrgent, isTrue);
  });

  test('done action respects incomplete checklist confirmation', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't6', title: 'Task 6', updatedAtMs: 10);
    final backend = _QuickActionBackend(
      initialTodos: [initial],
      checklistItemsByTodoId: <String, List<TodoChecklistItem>>{
        't6': const <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'c1',
            todoId: 't6',
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
        't6': TodoChecklistProgress(
          todoId: 't6',
          totalCount: 1,
          doneCount: 0,
        ),
      },
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.current('t6').status, 'done');
  });

  test('reopen action reopens done todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't7',
      title: 'Task 7',
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
    expect(backend.current('t7').status, 'open');
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

  Todo current(String id) => _todosById[id]!;

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
    return List<TodoChecklistItem>.from(
      _checklistItemsByTodoId[todoId] ?? const <TodoChecklistItem>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
