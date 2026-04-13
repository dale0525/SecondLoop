import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

void main() {
  setUp(() {
    clearTaskHubSharedAiCacheForTest();
    SharedPreferences.setMockInitialValues({});
  });

  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    String status = 'open',
    int? dueAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  testWidgets('adjust move up shows local feedback before delayed ai resolves',
      (tester) async {
    useLargeViewport(tester);
    final tomorrowMorning = DateTime.now()
        .add(const Duration(days: 1))
        .toUtc()
        .millisecondsSinceEpoch;
    final aiRelease = Completer<String>();
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Today task',
          updatedAtMs: 30,
          dueAtMs: DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 20,
          dueAtMs: tomorrowMorning,
        ),
        todo(
          id: 'b',
          title: 'Draft note',
          updatedAtMs: 10,
          dueAtMs: tomorrowMorning,
        ),
      ],
      taskPriorityAiResponseJson: '{"entries":[]}',
      taskPriorityAiResponseCompleter: aiRelease,
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubAdjustAction(
      tester,
      todoId: 'a',
      action: 'move_up',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );

    expect(find.text('AI calibrating'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Call vendor')).dy,
      lessThan(tester.getTopLeft(find.text('Draft note')).dy),
    );
  });

  testWidgets('adjust menu exposes move up down and restore ai actions',
      (tester) async {
    useLargeViewport(tester);
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 20,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 10,
        ),
      ],
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await openTaskHubAdjustMenu(tester, todoId: 'a');

    expect(find.text('Move Up a Bit'), findsOneWidget);
    expect(find.text('Move Down a Bit'), findsOneWidget);
    expect(find.text('Restore AI Order'), findsOneWidget);
  });

  testWidgets('pending badge clears after ai settles without changing position',
      (tester) async {
    useLargeViewport(tester);
    final aiRelease = Completer<String>();
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 20,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 10,
        ),
      ],
      taskPriorityAiResponseJson: '{"entries":[]}',
      taskPriorityAiResponseCompleter: aiRelease,
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubAdjustAction(
      tester,
      todoId: 'a',
      action: 'move_up',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );

    aiRelease.complete('{"entries":[]}');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsNothing,
    );
  });

  testWidgets(
      'pending badge still appears when refreshed todo normalizes last review timestamp',
      (tester) async {
    useLargeViewport(tester);
    final aiRelease = Completer<String>();
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 20,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 10,
        ),
      ],
      taskPriorityAiResponseJson: '{"entries":[]}',
      taskPriorityAiResponseCompleter: aiRelease,
      listTodosBehavior: (callCount, todos) async {
        final listed = todos.values.toList(growable: false);
        if (callCount != 2) {
          return listed;
        }
        return listed.map((todo) {
          if (todo.id != 'a') return todo;
          return Todo(
            id: todo.id,
            title: todo.title,
            dueAtMs: todo.dueAtMs,
            status: todo.status,
            sourceEntryId: todo.sourceEntryId,
            createdAtMs: todo.createdAtMs,
            updatedAtMs: todo.updatedAtMs,
            reviewStage: todo.reviewStage,
            nextReviewAtMs: todo.nextReviewAtMs,
            lastReviewAtMs: (todo.lastReviewAtMs ?? 0) + 1,
            manualImportanceNudgeScore: todo.manualImportanceNudgeScore,
            manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore,
          );
        }).toList(growable: false);
      },
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubQuickOverflowAction(
      tester,
      todoId: 'a',
      label: 'Tomorrow',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );

    aiRelease.complete('{"entries":[]}');
    await tester.pump();
    await tester.pumpAndSettle();
  });

  testWidgets('pending badge falls back to local-only when ai never resolves',
      (tester) async {
    useLargeViewport(tester);
    final aiRelease = Completer<String>();
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 20,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 10,
        ),
      ],
      taskPriorityAiResponseJson: '{"entries":[]}',
      taskPriorityAiResponseCompleter: aiRelease,
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubAdjustAction(
      tester,
      todoId: 'a',
      action: 'move_up',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsNothing,
    );
    expect(find.text('Using your local move for now.'), findsOneWidget);
  });

  testWidgets(
      'resolved refresh after local fallback does not replay stale animation',
      (tester) async {
    useLargeViewport(tester);
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 30,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 20,
        ),
        todo(
          id: 'b',
          title: 'Draft note',
          updatedAtMs: 10,
        ),
      ],
      taskPriorityAiResponseJson: '{"entries":[]}',
      taskPriorityAiResponseCallbacks: <Future<String> Function()>[
        () async => throw StateError('AI down'),
        () async => Future<String>.value(
              '{"entries":[{"todo_id":"b","semantic_adjustment":30,"reason":"AI promotes B","confidence":"high","is_important":true,"is_urgent":true}]}',
            ),
      ],
    );

    await tester.pumpWidget(
      wrapTaskHubTestApp(
        backend,
        syncEngine: engine,
      ),
    );
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubAdjustAction(
      tester,
      todoId: 'a',
      action: 'move_up',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_local_fallback_badge_a')),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('task_hub_priority_inline_animation_a'))
          .evaluate()
          .isEmpty,
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
      findsNothing,
    );

    engine.notifyExternalChange();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => backend.taskPriorityAiCallCount >= 3,
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
  });

  testWidgets(
      'inflight pre-action ai refresh does not clear pending state for a newer action',
      (tester) async {
    useLargeViewport(tester);
    final firstAiRelease = Completer<String>();
    final secondAiRelease = Completer<String>();
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        todo(
          id: 'focus',
          title: 'Fix prod issue',
          updatedAtMs: 30,
          status: 'in_progress',
        ),
        todo(
          id: 'a',
          title: 'Call vendor',
          updatedAtMs: 20,
        ),
        todo(
          id: 'b',
          title: 'Draft note',
          updatedAtMs: 10,
        ),
      ],
      taskPriorityAiResponseCallbacks: <Future<String> Function()>[
        () => firstAiRelease.future,
        () => secondAiRelease.future,
      ],
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await selectTaskHubAdjustAction(
      tester,
      todoId: 'a',
      action: 'move_up',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );

    firstAiRelease.complete(
      '{"entries":[{"todo_id":"b","semantic_adjustment":30,"reason":"AI promotes B","confidence":"high","is_important":true,"is_urgent":true}]}',
    );
    await tester.pump();
    await pumpUntil(
      tester,
      () => backend.taskPriorityAiCallCount >= 2,
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_local_fallback_badge_a')),
      findsNothing,
    );

    secondAiRelease.complete('{"entries":[]}');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsNothing,
    );
  });
}
