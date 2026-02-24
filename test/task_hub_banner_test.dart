import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_summary.dart';
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

  testWidgets('collapsed headline prioritizes overdue first', (tester) async {
    final now = DateTime(2026, 2, 24, 12);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        todo(
          id: 'overdue',
          title: 'Overdue',
          updatedAtMs: 1,
          dueAtMs: now
              .subtract(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'review',
          title: 'Review',
          updatedAtMs: 2,
          reviewStage: 0,
          nextReviewAtMs: now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(summary: summary),
          ),
        ),
      ),
    );

    expect(find.text('Today 1 • Overdue 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_agenda_banner')), findsNothing);
    expect(
        find.byKey(const ValueKey('todo_undetermined_banner')), findsNothing);
  });

  testWidgets('collapsed headline falls back to due-review when no overdue',
      (tester) async {
    final now = DateTime(2026, 2, 24, 12);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        todo(
          id: 'review',
          title: 'Review',
          updatedAtMs: 2,
          reviewStage: 0,
          nextReviewAtMs: now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(summary: summary),
          ),
        ),
      ),
    );

    expect(find.text('1 items need confirmation'), findsOneWidget);
  });

  testWidgets('collapsed headline shows today summary when due exists',
      (tester) async {
    final now = DateTime(2026, 2, 24, 12);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        todo(
          id: 'today',
          title: 'Today',
          updatedAtMs: 1,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(
          id: 'unscheduled',
          title: 'Unscheduled',
          updatedAtMs: 2,
        ),
      ],
      nowLocal: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(summary: summary),
          ),
        ),
      ),
    );

    expect(find.text('Today 1 • Overdue 0'), findsOneWidget);
    expect(find.text('Upcoming 0 · 1 unscheduled'), findsNothing);
  });

  testWidgets('expanded list exposes quick actions', (tester) async {
    final now = DateTime(2026, 2, 24, 12);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        todo(
          id: 'u1',
          title: 'Unscheduled Item',
          updatedAtMs: 1,
        ),
      ],
      nowLocal: now,
    );

    final calls = <(String todoId, TaskHubQuickAction action)>[];

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: TaskHubBanner(
              summary: summary,
              onQuickAction: (todo, action) async {
                calls.add((todo.id, action));
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task_hub_quick_u1_today')));
    await tester.pumpAndSettle();

    expect(calls.length, 1);
    expect(calls.first.$1, 'u1');
    expect(calls.first.$2, TaskHubQuickAction.today);
  });
}
