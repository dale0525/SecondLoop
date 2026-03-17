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

  testWidgets('backlog tasks expose start and tomorrow actions',
      (tester) async {
    final candidate = entry(
      todo: todo(id: 'u1', title: 'Backlog item', updatedAtMs: 10),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final layout = buildTaskHubQuickActionLayout(
                context,
                entry: candidate,
              );
              return Text(
                layout.$1.map((item) => item.label).join('|'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Start|Tomorrow'), findsOneWidget);
  });

  testWidgets('in-progress tasks expose done and tomorrow actions',
      (tester) async {
    final candidate = entry(
      todo: todo(
        id: 'u2',
        title: 'Review item',
        updatedAtMs: 10,
        status: 'in_progress',
      ),
      isUrgent: true,
      isImportant: true,
      band: TaskPriorityBand.focus,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final layout = buildTaskHubQuickActionLayout(
                context,
                entry: candidate,
              );
              return Text(
                layout.$1.map((item) => item.label).join('|'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Done|Tomorrow'), findsOneWidget);
  });

  testWidgets('done tasks expose reopen and more menu redo/delete actions',
      (tester) async {
    final candidate = entry(
      todo: todo(
        id: 'u3',
        title: 'Ship it',
        updatedAtMs: 10,
        status: 'done',
      ),
      band: TaskPriorityBand.done,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final layout = buildTaskHubQuickActionLayout(
                context,
                entry: candidate,
              );
              return Text(
                '${layout.$1.first.label}|${layout.$2.map((item) => item.label).join('|')}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Undo done|Do again|Delete'), findsOneWidget);
  });

  test('stale in-progress recovery signal is cleared before urgency increases',
      () async {
    SharedPreferences.setMockInitialValues({});

    final futureDue = DateTime.now().add(const Duration(days: 3));
    final initial = todo(
      id: 't-stale',
      title: 'Task stale',
      updatedAtMs: 10,
      dueAtMs: futureDue.toUtc().millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't-stale',
      const TaskPriorityManualSignal(preferredStatus: 'in_progress'),
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    final backlog = backend.current('t-stale');

    await controller.apply(backlog, TaskHubQuickAction.increaseUrgency);
    final scheduled = backend.current('t-stale');
    await controller.apply(scheduled, TaskHubQuickAction.increaseUrgency);

    final updated = backend.current('t-stale');
    expect(updated.status, isNot('in_progress'));
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

  test('decreasing then increasing urgency preserves in-progress state',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't3b',
      title: 'Task 3b',
      updatedAtMs: 10,
      status: 'in_progress',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final decreased =
        await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    expect(decreased, isNotNull);
    final afterDecrease = backend.current('t3b');
    expect(afterDecrease.status, 'open');
    expect(afterDecrease.dueAtMs, isNotNull);

    final increased = await controller.apply(
      afterDecrease,
      TaskHubQuickAction.increaseUrgency,
    );
    expect(increased, isNotNull);

    final restored = backend.current('t3b');
    expect(restored.status, 'in_progress');
    expect(restored.dueAtMs, isNull);
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

  test('decrease urgency keeps review tasks in the review queue', () async {
    SharedPreferences.setMockInitialValues({});

    final now = DateTime.now();
    final initial = todo(
      id: 't4b',
      title: 'Review this later',
      updatedAtMs: 10,
      status: 'inbox',
      reviewStage: 2,
      nextReviewAtMs: now
          .subtract(const Duration(minutes: 15))
          .toUtc()
          .millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket =
        await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    expect(ticket, isNotNull);

    final updated = backend.current('t4b');
    expect(updated.status, 'inbox');
    expect(updated.dueAtMs, isNull);
    expect(updated.reviewStage, initial.reviewStage);
    expect(updated.nextReviewAtMs, isNotNull);
    expect(updated.nextReviewAtMs,
        greaterThan(now.toUtc().millisecondsSinceEpoch));
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

  test('decrease urgency uses persisted effective urgency before todo fields',
      () async {
    SharedPreferences.setMockInitialValues({});

    final futureDue = DateTime.now().add(const Duration(days: 3));
    final initial = todo(
      id: 't5bb',
      title: 'Task 5bb',
      updatedAtMs: 10,
      dueAtMs: futureDue.toUtc().millisecondsSinceEpoch,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't5bb',
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

    final updated = backend.current('t5bb');
    expect(updated.status, 'open');
    expect(updated.dueAtMs, isNotNull);
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(updated.dueAtMs!, isUtc: true)
            .toLocal();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(dueLocal.year, tomorrow.year);
    expect(dueLocal.month, tomorrow.month);
    expect(dueLocal.day, tomorrow.day);
  });

  test('done clears stale in-progress recovery signal before reopen', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't5c',
      title: 'Task 5c',
      updatedAtMs: 10,
      status: 'in_progress',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    await controller.apply(initial, TaskHubQuickAction.decreaseUrgency);
    expect(
      (await signalStore.readForTodo('t5c'))?.preferredStatus,
      'in_progress',
    );

    final scheduled = backend.current('t5c');
    await controller.apply(scheduled, TaskHubQuickAction.done);
    expect((await signalStore.readForTodo('t5c'))?.preferredStatus, isNull);

    final doneTodo = backend.current('t5c');
    await controller.apply(doneTodo, TaskHubQuickAction.reopen);
    final reopened = backend.current('t5c');

    await controller.apply(reopened, TaskHubQuickAction.increaseUrgency);
    final finalTodo = backend.current('t5c');
    expect(finalTodo.status, 'in_progress');
    expect(finalTodo.dueAtMs, isNotNull);
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

  test('done action does not depend on scheduling settings loading', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': 'broken',
    });

    final initial = todo(id: 't6b', title: 'Task 6b', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.current('t6b').status, 'done');
  });

  test('importance actions do not depend on scheduling settings loading',
      () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': 'broken',
    });

    final initial = todo(id: 't6c', title: 'Task 6c', updatedAtMs: 10);
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
    expect((await signalStore.readForTodo('t6c'))?.isImportant, isTrue);
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
    final reopened = backend.current('t7');
    expect(reopened.status, 'in_progress');
    expect(reopened.dueAtMs, isNotNull);
  });

  test('start action moves unopened todo to in progress', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't8', title: 'Task 8', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);
    expect(ticket, isNotNull);
    expect(backend.current('t8').status, 'in_progress');
  });

  test('tomorrow action keeps in-progress status while moving due date',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't9',
      title: 'Task 9',
      updatedAtMs: 10,
      status: 'in_progress',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.tomorrow);
    expect(ticket, isNotNull);
    final updated = backend.current('t9');
    expect(updated.status, 'in_progress');
    expect(updated.dueAtMs, isNotNull);
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
