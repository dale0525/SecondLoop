import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('priority nudge shows local feedback before delayed ai resolves',
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

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_priority_a_urgency_increase')),
    );
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_a')),
      findsOneWidget,
    );
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

    await tester.tap(
      find.byKey(
          const ValueKey('task_hub_page_priority_a_importance_increase')),
    );
    await tester.pump();
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

    await tester.tap(
      find.byKey(
          const ValueKey('task_hub_page_priority_a_importance_increase')),
    );
    await tester.pump();
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
    expect(find.text('Using local priority for now.'), findsOneWidget);
  });
}
