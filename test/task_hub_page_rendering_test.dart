import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

void main() {
  setUp(() {
    clearTaskHubSharedAiCacheForTest();
  });

  testWidgets('task hub shows primary focus plus remaining sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final todayLater = now.add(const Duration(hours: 2));
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    final backend = TaskHubTestBackend(
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

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

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
    final backend = TaskHubTestBackend(
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

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    expect(
        find.byKey(const ValueKey('task_hub_page_ai_source')), findsOneWidget);
    expect(find.text('Live AI insight'), findsOneWidget);
    expect(find.text('Live AI result.'), findsOneWidget);
  });

  testWidgets('task hub entry card keeps expected quick controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
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

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    expect(
        find.byKey(const ValueKey('task_hub_page_item_focus')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_quick_focus_done')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('task_hub_feedback_focus')), findsOneWidget);
  });
}
