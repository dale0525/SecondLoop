import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
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
            semanticAdjustment: 24,
            reason: 'It unblocks the rest of today.',
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

  testWidgets('compact desktop banner keeps start action on the right',
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
          id: 'scheduled-1',
          title: 'Prepare weekly review summary',
          updatedAtMs: 20,
          dueAtMs:
              now.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
        ),
        todo(
            id: 'backlog-1', title: 'Triage product feedback', updatedAtMs: 30),
        todo(
            id: 'backlog-2', title: 'Review inbox follow-ups', updatedAtMs: 40),
        todo(
            id: 'backlog-3',
            title: 'Draft migration checklist',
            updatedAtMs: 50),
      ],
      nowLocal: now,
    );
    TaskHubQuickAction? tappedAction;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 670,
                height: 518,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 72),
                    TaskHubBanner(
                      snapshot: snapshot,
                      compact: true,
                      onQuickAction: (_, action) async {
                        tappedAction = action;
                      },
                    ),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_banner_quick_pair')), findsNothing);
    expect(find.byKey(const ValueKey('task_hub_banner_primary_action')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_secondary_action')),
        findsNothing);
    expect(find.byKey(const ValueKey('task_hub_banner_relative_time')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_banner_view_all')), findsNothing);
    expect(
        find.byKey(const ValueKey('task_hub_banner_open_focus')), findsNothing);
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsNothing);
    expect(find.text('Prepare weekly review summary'), findsNothing);
    expect(find.text('Current focus'), findsNothing);
    expect(find.text('Start'), findsNothing);
    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.text('Open task hub'), findsNothing);
    expect(find.text('Tomorrow'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_primary_action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsNothing);
    expect(tappedAction, TaskHubQuickAction.start);
  });

  testWidgets('compact mobile banner keeps quick action on the right',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug before customer follow-up',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
      ],
      nowLocal: now,
    );

    TaskHubQuickAction? tappedAction;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: TaskHubBanner(
                  snapshot: snapshot,
                  compact: true,
                  onQuickAction: (_, action) async {
                    tappedAction = action;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final bannerHeight =
        tester.getSize(find.byKey(const ValueKey('task_hub_banner'))).height;

    expect(
        find.byKey(const ValueKey('task_hub_banner_view_all')), findsNothing);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_banner_quick_pair')), findsNothing);
    expect(find.byKey(const ValueKey('task_hub_banner_primary_action')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_secondary_action')),
        findsNothing);
    expect(find.byKey(const ValueKey('task_hub_banner_relative_time')),
        findsOneWidget);
    expect(find.text('Current focus'), findsNothing);
    expect(find.text('Start'), findsNothing);
    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.text('Open task hub'), findsNothing);
    expect(find.text('Tomorrow'), findsNothing);

    final titleRect = tester.getRect(
      find.text('Fix billing bug before customer follow-up'),
    );
    final actionRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );
    expect(actionRect.left, greaterThan(titleRect.right));

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_primary_action')));
    await tester.pump();

    expect(tappedAction, TaskHubQuickAction.start);
    expect(bannerHeight, lessThan(180));
  });

  testWidgets('banner shows status and time quick actions for active focus',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'focus', title: 'Fix billing bug', updatedAtMs: 10),
      ],
      nowLocal: now,
    );
    TaskHubQuickAction? tappedAction;

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

    expect(find.byKey(const ValueKey('task_hub_banner_quick_pair')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_primary_action')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_secondary_action')),
        findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_secondary_action')));
    await tester.pump();

    expect(tappedAction, TaskHubQuickAction.tomorrow);
  });

  testWidgets(
      'banner still shows open focus action without quick actions enabled',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'focus', title: 'Fix billing bug', updatedAtMs: 10),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              snapshot: snapshot,
              onOpenTodo: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task_hub_banner_open_focus')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_banner_open_hub')), findsNothing);
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

  testWidgets('banner fallback subtitle uses unified open-task wording',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'focus', title: 'Fix billing bug', updatedAtMs: 20),
        todo(
          id: 'open-2',
          title: 'Prepare demo',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(days: 2)).toUtc().millisecondsSinceEpoch,
        ),
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

    expect(find.text('Open 1 • 0 done'), findsOneWidget);
  });

  testWidgets('banner omits task hub button in wrap-up state', (tester) async {
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
        find.byKey(const ValueKey('task_hub_banner_open_hub')), findsNothing);
    expect(
        find.byKey(const ValueKey('task_hub_banner_view_all')), findsNothing);
    expect(find.text('Open task hub'), findsNothing);
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
            semanticAdjustment: 18,
            reason: 'This can wait until later today.',
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

  testWidgets('banner subtitle counts remaining open tasks after focus',
      (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[todo(id: 'focus', title: 'Write launch plan', updatedAtMs: 10)],
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(find.text('Open 0 • 0 done'), findsOneWidget);
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
            semanticAdjustment: 24,
            reason: 'It unblocks the rest of today.',
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

  testWidgets('banner shows shared ai source label for shared cache',
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
            semanticAdjustment: 24,
            reason: 'Shared AI result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    ).copyWith(
      enhancementSource: TaskPriorityEnhancementSource.aiSharedCache,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task_hub_banner_ai_source')),
        findsOneWidget);
    expect(find.text('Shared AI insight'), findsOneWidget);
  });

  testWidgets('banner keeps AI header for cached enhancement snapshots',
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
            semanticAdjustment: 24,
            reason: 'Cached AI result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    ).copyWith(
      enhancementSource: TaskPriorityEnhancementSource.aiLocalCache,
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
    expect(find.text('Cached AI result.'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_ai_source')),
        findsOneWidget);
    expect(find.text('Cached AI insight'), findsOneWidget);
    expect(
      find.text(
          'Connect Cloud or BYOK to unlock smarter priority suggestions.'),
      findsNothing,
    );
  });

  testWidgets('banner shows live ai source label for fresh rerank snapshots',
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
            semanticAdjustment: 24,
            reason: 'Live AI result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    ).copyWith(
      enhancementSource: TaskPriorityEnhancementSource.aiLive,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(body: TaskHubBanner(snapshot: snapshot)),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task_hub_banner_ai_source')),
        findsOneWidget);
    expect(find.text('Live AI insight'), findsOneWidget);
  });

  testWidgets('compact banner still shows AI source label', (tester) async {
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 't1', title: 'Clarify launch checklist', updatedAtMs: 10)
      ],
      nowLocal: DateTime(2026, 3, 13, 10, 0),
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            semanticAdjustment: 24,
            reason: 'Live AI result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    ).copyWith(
      enhancementSource: TaskPriorityEnhancementSource.aiLive,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: TaskHubBanner(
                snapshot: snapshot,
                compact: true,
                onQuickAction: (_, __) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task_hub_banner_ai_source')),
        findsOneWidget);
    expect(find.text('Live AI insight'), findsOneWidget);
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
            semanticAdjustment: 8,
            reason: 'Needs a quick decision.',
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
            semanticAdjustment: 8,
            reason: 'Needs a quick decision.',
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

  testWidgets('banner preview relative time stays pinned to snapshot timestamp',
      (tester) async {
    final now = DateTime.now();
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Fix billing bug',
          updatedAtMs: 20,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(
          id: 'scheduled',
          title: 'Prepare demo',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(days: 2)).toUtc().millisecondsSinceEpoch,
        ),
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

    final initialRelativeTime = tester
        .widget<Text>(
          find.byKey(const ValueKey('task_hub_relative_time_scheduled')),
        )
        .data;
    expect(initialRelativeTime, isNotNull);

    await tester.pump(const Duration(days: 8));
    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('task_hub_relative_time_scheduled')),
          )
          .data,
      initialRelativeTime,
    );
  });
}
