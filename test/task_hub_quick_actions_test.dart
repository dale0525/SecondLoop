import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_quick_action_layout.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';
import 'task_hub_quick_actions_test_helpers.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
    int? reviewStage,
    int? nextReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
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
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
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

  testWidgets('future scheduled tasks do not expose tomorrow again',
      (tester) async {
    final tomorrowNoon = DateTime(2026, 3, 14, 12, 0);
    final candidate = entry(
      todo: todo(
        id: 'u2b',
        title: 'Already scheduled',
        updatedAtMs: 10,
        dueAtMs: tomorrowNoon.toUtc().millisecondsSinceEpoch,
      ),
      band: TaskPriorityBand.scheduled,
    ).copyWith(
      isFutureScheduled: true,
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

    expect(find.text('Start::Today|Done'), findsOneWidget);
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
                '${layout.$1.map((item) => item.action.name).join('|')}|${layout.$2.map((item) => item.action.name).join('|')}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('reopen|redo|dismiss'), findsOneWidget);
  });

  test('move up a bit stores encoded move intent markers', () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 't-move-up', title: 'Task move up', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.moveUpABit,
    );

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    expect(backend.current('t-move-up').manualUrgencyNudgeScore, 2);
    expect(backend.current('t-move-up').manualImportanceNudgeScore, 2);

    await controller.undo(ticket);
    expect(backend.current('t-move-up').manualUrgencyNudgeScore, 0);
  });

  test('move down a bit stores encoded move intent markers', () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 't-move-down', title: 'Task move down', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.moveDownABit,
    );

    expect(ticket, isNotNull);
    expect(backend.current('t-move-down').manualUrgencyNudgeScore, -2);
    expect(backend.current('t-move-down').manualImportanceNudgeScore, -2);
  });

  test('restore ai order clears existing manual nudges', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-restore',
      title: 'Task restore',
      updatedAtMs: 10,
      manualImportanceNudgeScore: 1,
      manualUrgencyNudgeScore: -1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.restoreAiOrder,
    );

    expect(ticket, isNotNull);
    expect(backend.current('t-restore').manualImportanceNudgeScore, 0);
    expect(backend.current('t-restore').manualUrgencyNudgeScore, 0);

    await controller.undo(ticket!);
    expect(backend.current('t-restore').manualImportanceNudgeScore, 1);
    expect(backend.current('t-restore').manualUrgencyNudgeScore, -1);
  });

  test('restore ai order returns null when backend leaves nudges unchanged',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-restore-noop',
      title: 'Task restore noop',
      updatedAtMs: 10,
      manualImportanceNudgeScore: 2,
      manualUrgencyNudgeScore: 2,
    );
    final backend = QuickActionBackendTestDouble(
      initialTodos: [initial],
      ignoreClearManualNudges: true,
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.restoreAiOrder,
    );

    expect(ticket, isNull);
    expect(backend.current('t-restore-noop').manualImportanceNudgeScore, 2);
    expect(backend.current('t-restore-noop').manualUrgencyNudgeScore, 2);
  });

  test('increase urgency only increments manual urgency score', () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 't-urgency', title: 'Task urgency', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseUrgency,
    );

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    expect(backend.current('t-urgency').manualUrgencyNudgeScore, 1);
    expect(backend.current('t-urgency').manualImportanceNudgeScore, 0);
    expect(backend.current('t-urgency').status, initial.status);
    expect(backend.current('t-urgency').dueAtMs, initial.dueAtMs);

    await controller.undo(ticket);
    expect(backend.current('t-urgency').manualUrgencyNudgeScore, 0);
  });

  test('legacy urgency action clears move encoding before applying signal',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-legacy-over-move',
      title: 'Task legacy over move',
      updatedAtMs: 10,
      manualImportanceNudgeScore: 2,
      manualUrgencyNudgeScore: 2,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.decreaseUrgency,
    );

    expect(ticket, isNotNull);
    expect(backend.current('t-legacy-over-move').manualUrgencyNudgeScore, -1);
    expect(backend.current('t-legacy-over-move').manualImportanceNudgeScore, 0);

    await controller.undo(ticket!);
    expect(backend.current('t-legacy-over-move').manualUrgencyNudgeScore, 2);
    expect(
      backend.current('t-legacy-over-move').manualImportanceNudgeScore,
      2,
    );
  });

  test('increase importance only increments manual importance score', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-importance',
      title: 'Task importance',
      updatedAtMs: 10,
      status: 'in_progress',
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseImportance,
    );

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    expect(backend.current('t-importance').manualImportanceNudgeScore, 1);
    expect(backend.current('t-importance').manualUrgencyNudgeScore, 0);
    expect(backend.current('t-importance').status, 'in_progress');

    await controller.undo(ticket);
    expect(backend.current('t-importance').manualImportanceNudgeScore, 0);
  });

  test('urgency-only change leaves unchanged importance field unpatched',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-urgency-null',
      title: 'Task urgency null',
      updatedAtMs: 10,
      manualImportanceNudgeScore: null,
      manualUrgencyNudgeScore: null,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseUrgency,
    );

    expect(ticket, isNotNull);
    expect(backend.lastTransitionManualImportanceNudgeScore, isNull);
    expect(backend.lastTransitionManualUrgencyNudgeScore, 1);
  });

  test('concurrent urgency increases stay at a single up nudge', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't-race', title: 'Task race', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    await Future.wait(<Future<TaskHubUndoTicket?>>[
      controller.apply(initial, TaskHubQuickAction.increaseUrgency),
      controller.apply(initial, TaskHubQuickAction.increaseUrgency),
    ]);

    expect(backend.current('t-race').manualUrgencyNudgeScore, 1);
  });

  test('increasing an already maxed urgency nudge is a no-op', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-urgency-max',
      title: 'Task urgency max',
      updatedAtMs: 10,
      manualUrgencyNudgeScore: 1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseUrgency,
    );

    expect(ticket, isNull);
    expect(backend.current('t-urgency-max').manualUrgencyNudgeScore, 1);
  });

  test('decrease urgency flips an existing up nudge and undo restores it',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't5b',
      title: 'Task 5b',
      updatedAtMs: 10,
      manualUrgencyNudgeScore: 1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.decreaseUrgency,
    );
    expect(ticket, isNotNull);
    expect(backend.current('t5b').manualUrgencyNudgeScore, -1);

    await controller.undo(ticket!);
    expect(backend.current('t5b').manualUrgencyNudgeScore, 1);
  });

  test('signal-only undo with previous manual signal does not upsert todo',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't5b2',
      title: 'Task 5b2',
      updatedAtMs: 10,
      manualImportanceNudgeScore: -1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseImportance,
    );

    expect(ticket, isNotNull);
    final upsertsBeforeUndo = backend.upsertTodoCalls;

    await controller.undo(ticket!);

    expect(backend.upsertTodoCalls, upsertsBeforeUndo);
    expect(backend.current('t5b2').manualImportanceNudgeScore, -1);
  });

  test('redo copies manual nudges to the new todo and undo clears them',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't-redo',
      title: 'Task redo',
      updatedAtMs: 10,
      status: 'done',
      manualImportanceNudgeScore: 1,
      manualUrgencyNudgeScore: -1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.redo,
    );
    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');

    final createdTodoId = ticket.createdTodoId;
    expect(createdTodoId, isNotNull);
    expect(backend.current(createdTodoId!).manualImportanceNudgeScore, 1);
    expect(backend.current(createdTodoId).manualUrgencyNudgeScore, -1);

    await controller.undo(ticket);
    expect(backend.current(createdTodoId).status, 'dismissed');
  });

  test('done action respects incomplete checklist confirmation', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't6', title: 'Task 6', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(
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

  test(
      'start action preserves backend auto-set due timestamp for null-due tasks',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 't6b-start', title: 'Task 6b start', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    expect(backend.current('t6b-start').status, 'in_progress');
    expect(backend.current('t6b-start').dueAtMs, isNotNull);
  });

  test('done action does not depend on scheduling settings loading', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': 'broken',
    });

    final initial = todo(id: 't6b', title: 'Task 6b', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(
      initial,
      TaskHubQuickAction.increaseImportance,
    );
    expect(ticket, isNotNull);
    expect(backend.current('t6c').manualImportanceNudgeScore, 1);
  });

  test('reopen action reopens done todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't7',
      title: 'Task 7',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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

  test('redo action enqueues followup generation for created todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't6n',
      title: 'Task 6 native',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = QuickActionBackendTestDouble(
      initialTodos: [initial],
      enableFollowupSuggestions: true,
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.redo);
    expect(ticket, isNotNull);
    expect(backend.enqueueTodoFollowupGenerationJobCalls, 1);
  });

  test('reopen action falls back to default settings when prefs are invalid',
      () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': 'broken',
    });

    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final initial = todo(
      id: 't7b',
      title: 'Task 7b',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
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

  test('redo action creates a new open todo and can undo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't6',
      title: 'Task 6',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);
    expect(ticket, isNotNull);
    expect(backend.current('t8').status, 'in_progress');
  });

  test('start action preserves existing due and review fields', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't8-preserve',
      title: 'Task 8 preserve',
      updatedAtMs: 10,
      status: 'open',
      dueAtMs: 24680,
      reviewStage: 2,
      nextReviewAtMs: 13579,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    final updated = backend.current('t8-preserve');
    expect(updated.status, 'in_progress');
    expect(updated.dueAtMs, initial.dueAtMs);
    expect(updated.reviewStage, initial.reviewStage);
    expect(updated.nextReviewAtMs, initial.nextReviewAtMs);
    expect(backend.transitionTodoCalls, 1);
    expect(backend.setTodoStatusCalls, 0);
  });

  test('start action clears inbox review scheduling fields', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't8-inbox',
      title: 'Task 8 inbox',
      updatedAtMs: 10,
      status: 'inbox',
      dueAtMs: 24680,
      reviewStage: 2,
      nextReviewAtMs: 13579,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    final updated = backend.current('t8-inbox');
    expect(updated.status, 'in_progress');
    expect(updated.dueAtMs, initial.dueAtMs);
    expect(updated.reviewStage, isNull);
    expect(updated.nextReviewAtMs, isNull);
  });

  test('start action uses status transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't8b', title: 'Task 8b', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.start);

    expect(ticket, isNotNull);
    expect(backend.transitionTodoCalls, 1);
    expect(backend.setTodoStatusCalls, 0);
    expect(backend.upsertTodoCalls, 0);
  });

  test('failed start transition does not clear manual nudges first', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't8b-fail',
      title: 'Task 8b fail',
      updatedAtMs: 10,
      manualImportanceNudgeScore: 1,
      manualUrgencyNudgeScore: -1,
    );
    final backend = QuickActionBackendTestDouble(
      initialTodos: [initial],
      failOnTransitionCall: 1,
    );
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    await expectLater(
      () => controller.apply(initial, TaskHubQuickAction.start),
      throwsStateError,
    );

    final current = backend.current('t8b-fail');
    expect(current.status, initial.status);
    expect(current.manualImportanceNudgeScore, 1);
    expect(current.manualUrgencyNudgeScore, -1);
  });

  test('tomorrow action is a no-op when task is already due tomorrow',
      () async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final dueTomorrow = DateTime(2026, 3, 14, 12, 0);
    final initial = todo(
      id: 't10c',
      title: 'Task 10c',
      updatedAtMs: 10,
      dueAtMs: dueTomorrow.toUtc().millisecondsSinceEpoch,
      manualImportanceNudgeScore: 1,
      reviewStage: 3,
      nextReviewAtMs: nowLocal
          .subtract(const Duration(hours: 1))
          .toUtc()
          .millisecondsSinceEpoch,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.tomorrow);

    expect(ticket, isNull);
    final current = backend.current('t10c');
    expect(current.dueAtMs, initial.dueAtMs);
    expect(current.reviewStage, initial.reviewStage);
    expect(current.nextReviewAtMs, initial.nextReviewAtMs);
    expect(current.manualImportanceNudgeScore, 1);
    expect(backend.transitionTodoCalls, 0);
  });

  test('today action reschedules overdue task later the same day', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': 21 * 60,
    });

    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final overdueEarlierToday = DateTime(2026, 3, 13, 8, 0);
    final initial = todo(
      id: 't-today-overdue',
      title: 'Task today overdue',
      updatedAtMs: 10,
      dueAtMs: overdueEarlierToday.toUtc().millisecondsSinceEpoch,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.today);

    expect(ticket, isNotNull);
    final updated = backend.current('t-today-overdue');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(updated.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal, DateTime(2026, 3, 13, 21, 0));
  });

  test('undo after start uses transition instead of full upsert', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't8c', title: 'Task 8c', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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

  test('today action falls back to next morning after day end', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': (8 * 60) + 15,
      'actions.review.day_end_minutes_v1': (21 * 60) + 45,
    });

    final nowLocal = DateTime(2026, 3, 13, 22, 30);
    final initial = todo(id: 't10a', title: 'Task 10a', updatedAtMs: 10);
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.today);

    expect(ticket, isNotNull);
    final updated = backend.current('t10a');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(updated.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal, DateTime(2026, 3, 14, 8, 15));
  });

  test('redo action falls back to next morning after day end', () async {
    SharedPreferences.setMockInitialValues({
      'actions.review.morning_minutes_v1': (8 * 60) + 15,
      'actions.review.day_end_minutes_v1': (21 * 60) + 45,
    });

    final nowLocal = DateTime(2026, 3, 13, 22, 30);
    final initial = todo(
      id: 't10a-redo',
      title: 'Task 10a redo',
      updatedAtMs: 10,
      status: 'done',
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      nowLocal: () => nowLocal,
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.redo);

    expect(ticket, isNotNull);
    final createdTodo = backend.all().firstWhere(
        (todo) => todo.id != initial.id && todo.status != 'dismissed');
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(createdTodo.dueAtMs!, isUtc: true)
            .toLocal();
    expect(dueLocal, DateTime(2026, 3, 14, 8, 15));
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
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
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

  test('redo action ignores legacy signal store failures', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(
      id: 't11',
      title: 'Task 11',
      updatedAtMs: 10,
      status: 'done',
      manualImportanceNudgeScore: 1,
      manualUrgencyNudgeScore: -1,
    );
    final backend = QuickActionBackendTestDouble(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.redo);

    expect(ticket, isNotNull);
    if (ticket == null) fail('expected undo ticket');
    final createdTodoId = ticket.createdTodoId;
    expect(createdTodoId, isNotNull);
    expect(backend.current(createdTodoId!).manualImportanceNudgeScore, 1);
    expect(backend.current(createdTodoId).manualUrgencyNudgeScore, -1);
    expect(backend.deleteTodoCalls, 0);
  });
}
