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

  testWidgets(
      'task hub clears pending priority UI state when post-action refresh fails',
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
      taskPriorityAiResponseJson: '{"entries":[]}',
      listTodosBehavior: (callCount, todos) async {
        if (callCount == 2) {
          throw StateError('refresh failed');
        }
        return todos.values.toList(growable: false);
      },
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('task_hub_page_quick_focus_tomorrow'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    await _pumpUntilFound(tester, find.byType(SnackBar));

    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task_hub_priority_inline_animation_focus')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_priority_pending_badge_focus')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('task_hub_priority_local_fallback_badge_focus'),
      ),
      findsNothing,
    );
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

  testWidgets('unfinished tasks show adjust affordance', (tester) async {
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
      find.byKey(const ValueKey('task_hub_page_adjust_urgent-important')),
      findsOneWidget,
    );
  });

  testWidgets(
      'due-today tasks keep adjust affordance without explicit move tag',
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
      find.byKey(const ValueKey('task_hub_page_adjust_due-today')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('task_hub_page_nudge_due-today')),
        findsNothing);
  });

  testWidgets('open rows keep actions compact and show reason as a chip',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Focus task',
          dueAtMs:
              now.add(const Duration(hours: 1)).toUtc().millisecondsSinceEpoch,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'ai-task',
          title: 'AI-ranked task',
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
      taskPriorityAiResponseJson:
          '{"entries":[{"todo_id":"ai-task","semantic_adjustment":24,"reason":"This sounds strategically important.","confidence":"high","is_important":true}]}',
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(const ValueKey('task_hub_page_quick_ai-task_start')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_quick_ai-task_tomorrow')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_quick_ai-task_more')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_adjust_ai-task')),
      findsOneWidget,
    );
    expect(find.text('AI promoted'), findsOneWidget);
    expect(find.text('This sounds strategically important.'), findsNothing);
    expect(
        find.byKey(const ValueKey('task_hub_feedback_ai-task')), findsNothing);
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

    await openTaskHubAdjustMenu(
      tester,
      todoId: 'snack-nudge',
    );
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_adjust_snack-nudge_move_up')),
    );
    await tester.pump();

    expect(find.text('Moved up a bit "Nudged from snackbar"'), findsOneWidget);
  });

  testWidgets('manual move tags use state wording', (tester) async {
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
          manualImportanceNudgeScore: 2,
          manualUrgencyNudgeScore: 2,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(find.text('Manually moved up'), findsOneWidget);
  });

  testWidgets('legacy urgency-only signals do not render manual move wording',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'legacy-urgency',
          title: 'Legacy urgency signal',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualUrgencyNudgeScore: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(find.text('Manually moved up'), findsNothing);
    expect(find.text('Manually moved down'), findsNothing);
  });

  testWidgets(
      'legacy importance-only signals do not render manual move wording',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'legacy-importance',
          title: 'Legacy importance signal',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(find.text('Manually moved up'), findsNothing);
    expect(find.text('Manually moved down'), findsNothing);
  });

  testWidgets('adjust affordance stays visible alongside current move tag',
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
          manualImportanceNudgeScore: 2,
          manualUrgencyNudgeScore: 2,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(const ValueKey('task_hub_page_adjust_nudged-control')),
      findsOneWidget,
    );
    expect(find.text('Manually moved up'), findsOneWidget);
  });

  testWidgets('relative time stays pinned to the snapshot timestamp',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Focus task',
          dueAtMs:
              now.add(const Duration(days: 2)).toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'done',
          title: 'Done task',
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

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    final initialRelativeTime = tester
        .widget<Text>(
            find.byKey(const ValueKey('task_hub_relative_time_focus')))
        .data;
    expect(initialRelativeTime, isNotNull);

    await tester.pump(const Duration(days: 8));
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_section_done_toggle')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('task_hub_relative_time_focus')),
          )
          .data,
      initialRelativeTime,
    );
  });

  testWidgets('done section does not render active relative-time labels',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Focus task',
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
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
          title: 'Finished task',
          dueAtMs: now
              .subtract(const Duration(days: 2))
              .toUtc()
              .millisecondsSinceEpoch,
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

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_section_done_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Finished task'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_relative_time_done')),
        findsNothing);
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
      find.byKey(const ValueKey('task_hub_page_quick_undo-highlight_more')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow').last);
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

  testWidgets('all tasks expose move-up and move-down adjust actions',
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

    await openTaskHubAdjustMenu(tester, todoId: 'guarded');

    expect(
      find.byKey(const ValueKey('task_hub_page_adjust_guarded_move_up')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task_hub_page_adjust_guarded_move_down')),
      findsOneWidget,
    );
  });

  testWidgets('backlog tasks expose restore ai order in adjust actions',
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

    await openTaskHubAdjustMenu(tester, todoId: 'open-task');

    expect(
      find.byKey(const ValueKey('task_hub_page_adjust_open-task_restore_ai')),
      findsOneWidget,
    );
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
}
