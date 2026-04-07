import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

void main() {
  setUp(() {
    clearTaskHubSharedAiCacheForTest();
  });

  testWidgets('same-section urgency increase animates without overlay',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    useLargeViewport(tester);
    final tomorrowMorning = DateTime.now()
        .add(const Duration(days: 1))
        .toUtc()
        .millisecondsSinceEpoch;
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Today task',
          dueAtMs: DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 100,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'a',
          title: 'Call vendor',
          dueAtMs: tomorrowMorning,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'b',
          title: 'Draft note',
          dueAtMs: tomorrowMorning,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_priority_a_urgency_increase')),
    );
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_a')),
      findsOneWidget,
    );
  });

  testWidgets('done action shows a flying overlay before settling in done',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    useLargeViewport(tester);
    final backend = TaskHubTestBackend(
      todos: const <Todo>[
        Todo(
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
          id: 'done',
          title: 'Already shipped',
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

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_focus_done')));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsOneWidget,
    );
  });

  testWidgets('offscreen destination degrades to non-flight animation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = TaskHubTestBackend(
      todos: List<Todo>.generate(
        28,
        (index) => Todo(
          id: index == 0 ? 'focus' : 'done-$index',
          title: index == 0 ? 'Fix prod issue' : 'Done $index',
          dueAtMs: null,
          status: index == 0 ? 'in_progress' : 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 100 - index,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ),
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_focus_done')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
  });

  testWidgets('reduced motion disables emphasized flight', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useLargeViewport(tester);
    final backend = TaskHubTestBackend(
      todos: const <Todo>[
        Todo(
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
          id: 'done',
          title: 'Already shipped',
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
      wrapTaskHubTestApp(
        backend,
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    await pumpUntilTaskHubReady(tester);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_focus_done')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
  });
}
