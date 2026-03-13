import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
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
}
