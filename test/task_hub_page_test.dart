import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) =>
    pumpUntil(
      tester,
      condition,
      step: step,
      maxPumps: maxPumps,
    );

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) =>
    pumpUntilFound(
      tester,
      finder,
      step: step,
      maxPumps: maxPumps,
    );

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) =>
    pumpUntilTaskHubReady(tester);

void _useLargeViewport(WidgetTester tester) => useLargeViewport(tester);

Widget _wrap(AppBackend backend, {SyncEngine? syncEngine}) =>
    wrapTaskHubTestApp(backend, syncEngine: syncEngine);

typedef _TaskHubBackend = TaskHubTestBackend;
typedef _NoopSyncRunner = NoopSyncRunner;

void main() {
  setUp(() {
    clearTaskHubSharedAiCacheForTest();
  });

  testWidgets(
      'task hub ignores cached ai result from a different resolved scope',
      (tester) async {
    final nowLocal = DateTime.now();
    final cacheScopeKey = buildTaskPriorityAiCacheScopeKey(
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://api.openai.com/v1',
      modelName: 'gpt-4o-mini',
      localeTag: 'en',
      partitionKey: '["p1","openai-compatible"]',
    );
    final requestSignature = jsonEncode(<String, Object?>{
      'time_bucket': buildTaskPriorityAiTimeBucket(nowLocal),
      'candidate': buildTaskPriorityAiRequest(
        buildTaskPrioritySnapshot(
          <Todo>[
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
          nowLocal: nowLocal,
        ),
        nowLocal: nowLocal,
      ).candidates.single.toJson(),
    });
    SharedPreferences.setMockInitialValues({
      'task_priority_ai_cache_v3': jsonEncode(<String, Object?>{
        'scopes': <String, Object?>{
          cacheScopeKey: <String, Object?>{
            'entries': <String, Object?>{
              'focus': TaskPriorityAiCachedAssessment(
                entry: const TaskPriorityAiEntry(
                  todoId: 'focus',
                  semanticAdjustment: 16,
                  reason: 'Cached AI result.',
                  confidence: TaskPriorityAiConfidence.high,
                ),
                requestSignature: requestSignature,
                computedAtLocal: nowLocal,
              ).toJson(),
            },
          },
        },
      }),
    });
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
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'p2',
          name: 'OpenAI Next',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'gpt-4.1-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(find.byKey(const ValueKey('task_hub_page_ai_source')), findsNothing);
    expect(find.text('Cached AI result.'), findsNothing);
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
    await tester.pump();

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_focus')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );

    await _pumpUntilFound(tester, find.textContaining('Save failed'));

    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('cancelling incomplete checklist confirmation does not animate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Checklist task',
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
      checklistProgress: const <TodoChecklistProgress>[
        TodoChecklistProgress(
          todoId: 'focus',
          doneCount: 0,
          totalCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('task_hub_page_quick_focus_done'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_focus')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_incomplete_checklist_dialog')),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_focus')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
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

    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_nudge_nudged_urgency_up'),
        ),
        matching: find.text('Urgency raised'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_nudge_nudged_importance_down'),
        ),
        matching: find.text('Importance lowered'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('priority controls show state wording inside the control',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'nudged-control',
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

    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('task_hub_page_priority_nudged-control_urgency_up'),
        ),
        matching: find.text('Urgency raised'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
              'task_hub_page_priority_nudged-control_importance_down'),
        ),
        matching: find.text('Importance lowered'),
      ),
      findsOneWidget,
    );
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

  testWidgets('task hub debounces sync-driven refresh bursts', (tester) async {
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
      llmProfiles: const <LlmProfile>[],
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );

    await tester.pumpWidget(_wrap(backend, syncEngine: engine));
    await _pumpUntilTaskHubReady(tester);

    final initialListTodosCalls = backend.listTodosCallCount;

    engine.notifyLocalMutation();
    engine.notifyLocalMutation();
    engine.notifyLocalMutation();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.listTodosCallCount, initialListTodosCalls);

    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntil(
      tester,
      () => backend.listTodosCallCount > initialListTodosCalls,
    );

    expect(backend.listTodosCallCount, initialListTodosCalls + 1);
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
