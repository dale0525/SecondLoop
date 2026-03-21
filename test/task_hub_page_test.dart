import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) {
  return _pumpUntil(
    tester,
    () =>
        find.byKey(const ValueKey('task_hub_page')).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
}

void _useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  setUp(() {
    BackendTaskPriorityAiService.clearSharedCacheForTest();
  });

  testWidgets('task hub shows primary focus plus remaining sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final todayLater = now.add(const Duration(hours: 2));
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: todayLater.toUtc().millisecondsSinceEpoch,
          status: 'open',
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
    await _pumpUntilTaskHubReady(tester);

    expect(find.byKey(const ValueKey('task_hub_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_focus')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_focus')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task_hub_checklist_progress_focus')),
      findsOneWidget,
    );
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Draft roadmap'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('task_hub_page_section_done')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_page_item_done')), findsOneWidget);
  });

  testWidgets('task hub shows live ai source label when rerank succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
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
      taskPriorityAiResponseJson: jsonEncode(
        const TaskPriorityAiBatchResult(
          entries: <TaskPriorityAiEntry>[
            TaskPriorityAiEntry(
              todoId: 'focus',
              semanticAdjustment: 16,
              reason: 'Live AI result.',
              confidence: TaskPriorityAiConfidence.high,
            ),
          ],
        ).toJson(),
      ),
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(
        find.byKey(const ValueKey('task_hub_page_ai_source')), findsOneWidget);
    expect(find.text('Live AI insight'), findsOneWidget);
    expect(find.text('Live AI result.'), findsOneWidget);
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
      failTransition: true,
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('task_hub_page_quick_focus_tomorrow'),
      ),
    );
    await _pumpUntilFound(tester, find.textContaining('Save failed'));

    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('unfinished tasks show score-driven priority controls',
      (tester) async {
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
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(const ValueKey(
          'task_hub_page_priority_urgent-important_urgency_neutral')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(
          'task_hub_page_priority_urgent-important_importance_neutral')),
      findsOneWidget,
    );
  });

  testWidgets('due-today urgency does not appear as an explicit urgency boost',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'due-today',
          title: 'Due today task',
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
          status: 'open',
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
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(
          const ValueKey('task_hub_page_priority_due-today_urgency_neutral')),
      findsOneWidget,
    );
  });

  testWidgets('manual nudge snackbar uses state wording', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'snack-nudge',
          title: 'Nudged from snackbar',
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
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('task_hub_page_priority_snack-nudge_urgency_increase'),
      ),
    );
    await tester.pump();

    expect(find.text('Urgency raised "Nudged from snackbar"'), findsOneWidget);
  });

  testWidgets('manual nudge pills use state wording', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'nudged',
          title: 'Nudged task',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualUrgencyNudgeScore: 1,
          manualImportanceNudgeScore: -1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(find.text('Urgency raised'), findsOneWidget);
    expect(find.text('Importance lowered'), findsOneWidget);
  });

  testWidgets('undo highlights the restored card without extra snackbar',
      (tester) async {
    _useLargeViewport(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'focus-anchor',
          title: 'Anchor',
          dueAtMs: now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'undo-highlight',
          title: 'Target',
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
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_quick_undo-highlight_tomorrow')),
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey(
                  'task_hub_page_item_state_undo-highlight_restored'))
              .evaluate()
              .isNotEmpty &&
          find.byType(SnackBar).evaluate().isEmpty,
    );

    expect(
      find.byKey(
        const ValueKey('task_hub_page_item_state_undo-highlight_restored'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('undo highlight also applies to restored primary focus',
      (tester) async {
    _useLargeViewport(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus-undo',
          title: 'Focus',
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
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_quick_focus-undo_tomorrow')),
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey(
                  'task_hub_page_item_state_focus-undo_restored'))
              .evaluate()
              .isNotEmpty &&
          find.byType(SnackBar).evaluate().isEmpty,
    );

    expect(
      find.byKey(
        const ValueKey('task_hub_page_item_state_focus-undo_restored'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('all tasks keep positive priority buttons enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'guarded',
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
    await _pumpUntilTaskHubReady(tester);

    final urgencyIncrease = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_priority_guarded_urgency_increase'),
        ),
        matching: find.byType(InkWell),
      ),
    );
    final importanceIncrease = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_priority_guarded_importance_increase'),
        ),
        matching: find.byType(InkWell),
      ),
    );
    final urgencyDecrease = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_priority_guarded_urgency_decrease'),
        ),
        matching: find.byType(InkWell),
      ),
    );

    expect(urgencyIncrease.onTap, isNotNull);
    expect(importanceIncrease.onTap, isNotNull);
    expect(urgencyDecrease.onTap, isNotNull);
  });

  testWidgets('backlog tasks keep positive priority buttons enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'open-task',
          title: 'Plan next step',
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
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    final urgencyIncrease = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_priority_open-task_urgency_increase'),
        ),
        matching: find.byType(InkWell),
      ),
    );
    final importanceIncrease = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(
          const ValueKey(
              'task_hub_page_priority_open-task_importance_increase'),
        ),
        matching: find.byType(InkWell),
      ),
    );

    expect(urgencyIncrease.onTap, isNotNull);
    expect(importanceIncrease.onTap, isNotNull);
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
    await _pumpUntilTaskHubReady(tester);

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

  testWidgets('done more menu keeps delete separated and last', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
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

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await _pumpUntilFound(tester, find.text('Delete'));

    expect(find.text('Do again'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);

    final redoTopLeft = tester.getTopLeft(find.text('Do again'));
    final deleteTopLeft = tester.getTopLeft(find.text('Delete'));
    expect(redoTopLeft.dy, lessThan(deleteTopLeft.dy));
  });

  testWidgets('unfinished more menu marks today as neutral', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'open',
          title: 'Plan next step',
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
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_open_more')));
    await tester.pumpAndSettle();

    final todayContext = tester.element(find.text('Today'));
    final expectedColor = Theme.of(todayContext).colorScheme.onSurfaceVariant;
    final todayText = tester.widget<Text>(find.text('Today'));
    final todayIcon = tester.widget<Icon>(find.byIcon(Icons.today_rounded));

    expect(todayText.style?.color, expectedColor);
    expect(todayIcon.color, expectedColor);
  });

  testWidgets('done more menu marks redo as secondary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
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

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await _pumpUntilFound(tester, find.text('Do again'));

    final redoContext = tester.element(find.text('Do again'));
    final expectedColor = Theme.of(redoContext).colorScheme.onSurfaceVariant;
    final redoText = tester.widget<Text>(find.text('Do again'));
    final redoIcon = tester.widget<Icon>(find.byIcon(Icons.replay_rounded));

    expect(redoText.style?.color, expectedColor);
    expect(redoIcon.color, expectedColor);
  });

  testWidgets('done more menu marks delete as destructive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
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

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await tester.pumpAndSettle();

    final deleteContext = tester.element(find.text('Delete'));
    final expectedColor = Theme.of(deleteContext).colorScheme.error;
    final deleteText = tester.widget<Text>(find.text('Delete'));
    final deleteIcon =
        tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded));

    expect(deleteText.style?.color, expectedColor);
    expect(deleteIcon.color, expectedColor);
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
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_done_load_more')));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_item_done-0')),
    );

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
    this.failTransition = false,
    this.taskPriorityAiResponseJson,
  })  : _todos = {for (final todo in todos) todo.id: todo},
        _checklistProgress =
            List<TodoChecklistProgress>.from(checklistProgress);

  final Map<String, Todo> _todos;
  final List<TodoChecklistProgress> _checklistProgress;
  final bool failTransition;
  final String? taskPriorityAiResponseJson;

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
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
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
      manualImportanceNudgeScore: manualImportanceNudgeScore ??
          _todos[id]?.manualImportanceNudgeScore ??
          0,
      manualUrgencyNudgeScore:
          manualUrgencyNudgeScore ?? _todos[id]?.manualUrgencyNudgeScore ?? 0,
    );
    _todos[id] = updated;
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
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    if (failTransition) {
      throw StateError('apply failed');
    }
    final existing = _todos[todoId]!;
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
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? 0
          : (manualImportanceNudgeScore ??
              existing.manualImportanceNudgeScore ??
              0),
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? 0
          : (manualUrgencyNudgeScore ?? existing.manualUrgencyNudgeScore ?? 0),
    );
    _todos[todoId] = updated;
    return updated;
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    if (taskPriorityAiResponseJson == null) {
      throw UnimplementedError('taskPriorityRerankAi');
    }
    return taskPriorityAiResponseJson!;
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
      manualImportanceNudgeScore: existing.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: existing.manualUrgencyNudgeScore,
    );
    _todos[todoId] = updated;
    return updated;
  }
}
