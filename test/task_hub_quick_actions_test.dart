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
  setUp(TaskPrioritySignalStore.resetMutationQueueForTest);

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

  testWidgets('unfinished tasks keep done in secondary actions',
      (tester) async {
    final candidate = entry(
      todo: todo(id: 'u1b', title: 'Backlog item', updatedAtMs: 10),
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
                '${layout.$1.map((item) => item.label).join('|')}::${layout.$2.map((item) => item.label).join('|')}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Start|Tomorrow::Today|Done'), findsOneWidget);
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

    expect(find.text('Resume today|Do again|Delete'), findsOneWidget);
  });

  test('increase urgency only increments manual urgency score', () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 't-urgency', title: 'Task urgency', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseUrgency,
    );

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    expect((await signalStore.readForTodo('t-urgency'))?.urgencyScore, 1);
    expect(backend.current('t-urgency').status, initial.status);
    expect(backend.current('t-urgency').dueAtMs, initial.dueAtMs);

    await controller.undo(ticket);
    expect(await signalStore.readForTodo('t-urgency'), isNull);
  });

  test('increase importance only increments manual importance score', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-importance',
      title: 'Task importance',
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

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseImportance,
    );

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    expect((await signalStore.readForTodo('t-importance'))?.importanceScore, 1);
    expect(backend.current('t-importance').status, 'in_progress');

    await controller.undo(ticket);
    expect(await signalStore.readForTodo('t-importance'), isNull);
  });

  test('concurrent urgency increases preserve both increments', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't-race', title: 'Task race', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final signalStore = _RaceySignalStore();
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    await Future.wait(<Future<TaskHubUndoTicket?>>[
      controller.apply(initial, TaskHubQuickAction.increaseUrgency),
      controller.apply(initial, TaskHubQuickAction.increaseUrgency),
    ]);

    expect((await signalStore.readForTodo('t-race'))?.urgencyScore, 2);
  });

  test(
      'decrease urgency decrements existing urgency score and undo restores it',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't5b', title: 'Task 5b', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't5b',
      const TaskPriorityManualSignal(urgencyScore: 2),
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
    expect((await signalStore.readForTodo('t5b'))?.urgencyScore, 1);

    await controller.undo(ticket!);
    expect((await signalStore.readForTodo('t5b'))?.urgencyScore, 2);
  });

  test('signal-only undo with previous manual signal does not upsert todo',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't5b2', title: 'Task 5b2', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't5b2',
      const TaskPriorityManualSignal(isImportant: false),
    );
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
    final upsertsBeforeUndo = backend.upsertTodoCalls;

    await controller.undo(ticket!);

    expect(backend.upsertTodoCalls, upsertsBeforeUndo);
    expect((await signalStore.readForTodo('t5b2'))?.importanceScore, -1);
  });

  test('redo copies manual scores to the new todo and undo clears them',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-redo',
      title: 'Task redo',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    const signalStore = TaskPrioritySignalStore();
    await signalStore.setForTodo(
      't-redo',
      const TaskPriorityManualSignal(
        importanceScore: 3,
        urgencyScore: -2,
      ),
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: signalStore,
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.redo,
    );
    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');

    final createdTodoId = ticket.createdTodoId;
    expect(createdTodoId, isNotNull);
    expect((await signalStore.readForTodo(createdTodoId!))?.importanceScore, 3);
    expect((await signalStore.readForTodo(createdTodoId))?.urgencyScore, -2);

    await controller.undo(ticket);
    expect(await signalStore.readForTodo(createdTodoId), isNull);
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
    expect(backend.transitionTodoCalls, 1);
    expect(backend.upsertTodoCalls, 0);
  });

  test('reopen action falls back to default settings when prefs are invalid',
      () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': 'broken',
    });

    final initial = todo(
      id: 't7b',
      title: 'Task 7b',
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
    final reopened = backend.current('t7b');
    expect(reopened.status, 'in_progress');
    expect(reopened.dueAtMs, isNotNull);

    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(reopened.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal.hour, 21);
    expect(dueLocal.minute, 0);
  });

  test('reopen action uses next morning when day end already passed', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': (8 * 60) + 15,
      'actions.review.day_end_minutes_v1': (21 * 60) + 45,
    });

    final nowLocal = DateTime(2026, 3, 13, 22, 30);
    final initial = todo(
      id: 't7c',
      title: 'Task 7c',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.reopen);

    expect(ticket, isNotNull);
    final reopened = backend.current('t7c');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(reopened.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal, DateTime(2026, 3, 14, 8, 15));
  });

  test('undo after reopen uses transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't7d',
      title: 'Task 7d',
      updatedAtMs: 10,
      status: 'done',
      dueAtMs: 123456789,
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.reopen);

    expect(ticket, isNotNull);
    final transitionsBeforeUndo = backend.transitionTodoCalls;
    final upsertsBeforeUndo = backend.upsertTodoCalls;

    await controller.undo(ticket!);

    final restored = backend.current('t7d');
    expect(restored.status, 'done');
    expect(restored.dueAtMs, initial.dueAtMs);
    expect(backend.transitionTodoCalls, transitionsBeforeUndo + 1);
    expect(backend.upsertTodoCalls, upsertsBeforeUndo);
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

  test('start action uses status transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't8b', title: 'Task 8b', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    expect(backend.setTodoStatusCalls, 1);
    expect(backend.upsertTodoCalls, 0);
  });

  test('undo after start uses transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't8c', title: 'Task 8c', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    final transitionsBeforeUndo = backend.transitionTodoCalls;
    final upsertsBeforeUndo = backend.upsertTodoCalls;

    await controller.undo(ticket!);

    expect(backend.current('t8c').status, 'open');
    expect(backend.transitionTodoCalls, transitionsBeforeUndo + 1);
    expect(backend.upsertTodoCalls, upsertsBeforeUndo);
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
    expect(backend.transitionTodoCalls, 1);
    expect(backend.upsertTodoCalls, 0);
  });

  test('tomorrow action uses morning time for due date', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': (8 * 60) + 15,
      'actions.review.day_end_minutes_v1': (21 * 60) + 45,
    });

    final initial = todo(id: 't10', title: 'Task 10', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.tomorrow);

    expect(ticket, isNotNull);
    final updated = backend.current('t10');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(updated.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal.hour, 8);
    expect(dueLocal.minute, 15);
  });

  test('undo after tomorrow uses transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't10b',
      title: 'Task 10b',
      updatedAtMs: 10,
      dueAtMs: 987654321,
      status: 'in_progress',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.tomorrow);

    expect(ticket, isNotNull);
    final transitionsBeforeUndo = backend.transitionTodoCalls;
    final upsertsBeforeUndo = backend.upsertTodoCalls;

    await controller.undo(ticket!);

    final restored = backend.current('t10b');
    expect(restored.status, 'in_progress');
    expect(restored.dueAtMs, initial.dueAtMs);
    expect(backend.transitionTodoCalls, transitionsBeforeUndo + 1);
    expect(backend.upsertTodoCalls, upsertsBeforeUndo);
  });

  test('redo action rolls back created todo when signal copy fails', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't11',
      title: 'Task 11',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      signalStore: const _FailingSignalStore(),
    );

    await expectLater(
      () => controller.apply(initial, TaskHubQuickAction.redo),
      throwsA(isA<StateError>()),
    );

    final nonDismissedNewTodos = backend
        .all()
        .where((todo) => todo.id != initial.id && todo.status != 'dismissed')
        .toList(growable: false);
    expect(nonDismissedNewTodos, isEmpty);
    expect(backend.deleteTodoCalls, 1);
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
  var upsertTodoCalls = 0;
  var transitionTodoCalls = 0;
  var deleteTodoCalls = 0;
  var setTodoStatusCalls = 0;

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
    upsertTodoCalls += 1;
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
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    String? sourceMessageId,
  }) async {
    transitionTodoCalls += 1;
    final existing = _todosById[todoId]!;
    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? existing.dueAtMs),
      status: newStatus ?? existing.status,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage:
          clearReviewStage ? null : (reviewStage ?? existing.reviewStage),
      nextReviewAtMs: clearNextReviewAtMs
          ? null
          : (nextReviewAtMs ?? existing.nextReviewAtMs),
      lastReviewAtMs: clearLastReviewAtMs
          ? null
          : (lastReviewAtMs ?? existing.lastReviewAtMs),
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
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
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    deleteTodoCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) return;
    _todosById[todoId] = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: 'dismissed',
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingSignalStore extends TaskPrioritySignalStore {
  const _FailingSignalStore();

  @override
  Future<TaskPriorityManualSignal?> readForTodo(String todoId) async {
    return const TaskPriorityManualSignal(importanceScore: 1);
  }

  @override
  Future<void> setForTodo(
    String todoId,
    TaskPriorityManualSignal signal,
  ) {
    throw StateError('signal write failed');
  }
}

final class _RaceySignalStore extends TaskPrioritySignalStore {
  _RaceySignalStore();

  TaskPriorityManualSignal? _signal;
  var _staleReadCount = 0;

  @override
  Future<TaskPriorityManualSignal?> readForTodo(String todoId) async {
    if (_staleReadCount < 2) {
      _staleReadCount += 1;
      return null;
    }
    return _signal;
  }

  @override
  Future<void> setForTodo(
    String todoId,
    TaskPriorityManualSignal signal,
  ) async {
    _signal = signal.isEmpty ? null : signal;
  }

  @override
  Future<TaskPrioritySignalMutation> mutateForTodo(
    String todoId,
    TaskPriorityManualSignal Function(TaskPriorityManualSignal current) mutate,
  ) async {
    final previous = _signal;
    final updated = mutate(previous ?? const TaskPriorityManualSignal());
    _signal = updated.isEmpty ? null : updated;
    _staleReadCount = 2;
    return TaskPrioritySignalMutation(previous: previous, updated: updated);
  }
}
