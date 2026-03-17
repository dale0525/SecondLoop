import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
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

  testWidgets('banner defaults to focus card with AI reason when available',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 't1', title: 'Clarify launch checklist', updatedAtMs: 10)
      ],
      nowLocal: now,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 24,
            reason: 'It unblocks the rest of today.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(find.text('AI recommends this now'), findsOneWidget);
    expect(find.text('Clarify launch checklist'), findsOneWidget);
    expect(find.text('It unblocks the rest of today.'), findsOneWidget);
  });

  testWidgets('banner expands preview list with scheduled and decide items',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(
          id: 'scheduled',
          title: 'Prepare demo',
          updatedAtMs: 20,
          dueAtMs:
              now.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
        ),
        todo(id: 'decide', title: 'Triage backlog', updatedAtMs: 30),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_item_scheduled')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_item_decide')),
        findsOneWidget);
  });

  testWidgets('banner preview shows checklist progress summary',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(id: 'decide', title: 'Triage backlog', updatedAtMs: 30),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              checklistProgressByTodoId: const <String, TodoChecklistProgress>{
                'decide': TodoChecklistProgress(
                  todoId: 'decide',
                  totalCount: 3,
                  doneCount: 1,
                ),
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_checklist_progress_decide')),
      findsOneWidget,
    );
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('banner shows wrap-up state when no focus remains',
      (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      const <Todo>[
        Todo(
          id: 'done-only',
          title: 'Done only',
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
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(find.text('Wrap up'), findsOneWidget);
    expect(find.text('No urgent task right now'), findsOneWidget);
  });

  testWidgets('banner shows only one open task hub button in wrap-up state',
      (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      const <Todo>[
        Todo(
          id: 'done-only',
          title: 'Done only',
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
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('task_hub_banner_open_hub')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_banner_view_all')), findsNothing);
  });

  testWidgets('banner primary action uses shared quick action mapping',
      (tester) async {
    TaskHubQuickAction? tappedAction;
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[todo(id: 't1', title: 'Write launch plan', updatedAtMs: 10)],
      nowLocal: DateTime(2026, 3, 13, 10, 0),
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 18,
            reason: 'This can wait until later today.',
            suggestedAction: TaskPrioritySuggestionKind.defer,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              onQuickAction: (entry, action) async {
                tappedAction = action;
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_primary_action')));
    await tester.pump();

    expect(tappedAction, TaskHubQuickAction.start);
  });

  testWidgets('banner shows AI upgrade hint when enhancement is unavailable',
      (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[todo(id: 't1', title: 'Schedule next week', updatedAtMs: 10)],
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              showAiUpgradeHint: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
          'Connect Cloud or BYOK to unlock smarter priority suggestions.'),
      findsOneWidget,
    );
  });

  testWidgets('banner hides AI upgrade hint when AI reason is already shown',
      (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 't1', title: 'Clarify launch checklist', updatedAtMs: 10)
      ],
      nowLocal: DateTime(2026, 3, 13, 10, 0),
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 24,
            reason: 'It unblocks the rest of today.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              showAiUpgradeHint: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('AI recommends this now'), findsOneWidget);
    expect(find.text('It unblocks the rest of today.'), findsOneWidget);
    expect(
      find.text(
          'Connect Cloud or BYOK to unlock smarter priority suggestions.'),
      findsNothing,
    );
  });

  testWidgets('banner preview quick action invokes callback', (tester) async {
    TaskHubQuickAction? tappedAction;
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(id: 'decide', title: 'Triage backlog', updatedAtMs: 30),
      ],
      nowLocal: now,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'decide',
            priorityBand: TaskPriorityAiBand.next,
            semanticAdjustment: 8,
            reason: 'Needs a quick decision.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.medium,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              onQuickAction: (entry, action) async {
                tappedAction = action;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_decide_start')));
    await tester.pump();

    expect(tappedAction, TaskHubQuickAction.start);
  });

  testWidgets('banner preview more menu opens actions', (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(id: 'decide', title: 'Triage backlog', updatedAtMs: 30),
      ],
      nowLocal: now,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'decide',
            priorityBand: TaskPriorityAiBand.next,
            semanticAdjustment: 8,
            reason: 'Needs a quick decision.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.medium,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_decide_more')));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
  });
}
