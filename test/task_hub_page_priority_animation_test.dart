import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
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

  testWidgets('done flight starts from the scrolled source position',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = TaskHubTestBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 100,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'backlog-a',
          title: 'Backlog A',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'backlog-b',
          title: 'Backlog B',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
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
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    final sourceFinder = find.byKey(const ValueKey('task_hub_page_item_focus'));
    final preScrollRect = tester.getRect(sourceFinder);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -24));
    await tester.pumpAndSettle();

    final sourceRect = tester.getRect(sourceFinder);
    expect((preScrollRect.top - sourceRect.top).abs(), greaterThan(0));
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_quick_focus_done')),
    );
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect((overlayRect.top - sourceRect.top).abs(), lessThan(8));
    expect((overlayRect.left - sourceRect.left).abs(), lessThan(8));
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
          id: 'backlog',
          title: 'Plan next step',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
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
    final sourceRect =
        tester.getRect(find.byKey(const ValueKey('task_hub_page_item_focus')));

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
    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect((overlayRect.top - sourceRect.top).abs(), lessThan(8));
    expect((overlayRect.left - sourceRect.left).abs(), lessThan(8));
  });

  testWidgets('offscreen destination still shows directional animation',
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

    final sourceRect =
        tester.getRect(find.byKey(const ValueKey('task_hub_page_item_focus')));
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_focus_done')));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect((overlayRect.top - sourceRect.top).abs(), lessThan(8));
    expect((overlayRect.left - sourceRect.left).abs(), lessThan(8));
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

  testWidgets('destination outside animation layer falls back to source motion',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 320);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -132));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_quick_done_reopen')),
      24,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 84));
    await tester.pumpAndSettle();

    final sourceRect =
        tester.getRect(find.byKey(const ValueKey('task_hub_page_item_done')));
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_reopen')));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect((overlayRect.top - sourceRect.top).abs(), lessThan(8));
    expect((overlayRect.left - sourceRect.left).abs(), lessThan(8));
  });

  testWidgets('redo animates from the done card to the inserted task',
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
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final sourceRect =
        tester.getRect(find.byKey(const ValueKey('task_hub_page_item_done')));

    final moreButtonState =
        tester.state<PopupMenuButtonState<TaskHubQuickAction>>(
      find.descendant(
        of: find.byKey(const ValueKey('task_hub_page_quick_done_more')),
        matching: find.byType(PopupMenuButton<TaskHubQuickAction>),
      ),
    );
    moreButtonState.showButtonMenu();
    await pumpUntilFound(tester, find.text('Do again'));
    Navigator.of(tester.element(find.byType(ListView))).pop(
      TaskHubQuickAction.redo,
    );
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect((overlayRect.top - sourceRect.top).abs(), lessThan(8));
    expect((overlayRect.left - sourceRect.left).abs(), lessThan(8));
  });
}
