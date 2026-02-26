import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_summary.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('classifies todos into scheduled/unscheduled/review buckets', () {
    final nowLocal = DateTime(2026, 2, 24, 12, 0);

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

    final todos = <Todo>[
      todo(
        id: 'due-overdue',
        title: 'Overdue',
        updatedAtMs: 100,
        dueAtMs: nowLocal
            .subtract(const Duration(days: 1))
            .toUtc()
            .millisecondsSinceEpoch,
      ),
      todo(
        id: 'due-today',
        title: 'Today',
        updatedAtMs: 200,
        dueAtMs: nowLocal
            .add(const Duration(hours: 2))
            .toUtc()
            .millisecondsSinceEpoch,
      ),
      todo(
        id: 'due-upcoming',
        title: 'Upcoming',
        updatedAtMs: 300,
        dueAtMs: nowLocal
            .add(const Duration(days: 3))
            .toUtc()
            .millisecondsSinceEpoch,
      ),
      todo(
        id: 'unscheduled-a',
        title: 'Unscheduled A',
        updatedAtMs: 450,
      ),
      todo(
        id: 'review-due',
        title: 'Review Due',
        updatedAtMs: 400,
        status: 'inbox',
        reviewStage: 0,
        nextReviewAtMs: nowLocal
            .subtract(const Duration(hours: 1))
            .toUtc()
            .millisecondsSinceEpoch,
      ),
      todo(
        id: 'done-older',
        title: 'Done older',
        updatedAtMs: 900,
        status: 'done',
      ),
      todo(
        id: 'done-latest',
        title: 'Done latest',
        updatedAtMs: 950,
        status: 'done',
      ),
    ];

    final summary = TaskHubSummary.fromTodos(
      todos,
      nowLocal: nowLocal,
      scheduledPreviewLimit: 4,
      unscheduledPreviewLimit: 4,
    );

    expect(summary.dueCount, 2);
    expect(summary.overdueCount, 1);
    expect(summary.upcomingCount, 1);
    expect(summary.unscheduledCount, 2);
    expect(summary.dueReviewCount, 1);
    expect(summary.doneCount, 2);

    expect(
      summary.scheduledPreviewTodos.map((e) => e.id).toList(growable: false),
      <String>['due-overdue', 'due-today', 'due-upcoming'],
    );
    expect(
      summary.unscheduledPreviewTodos.map((e) => e.id).toList(growable: false),
      <String>['review-due', 'unscheduled-a'],
    );
    expect(
      summary.doneTodos.map((e) => e.id).toList(growable: false),
      <String>['done-latest', 'done-older'],
    );
    expect(summary.hasOverdue, isTrue);
    expect(summary.hasDueReview, isTrue);
  });

  test('keeps done todos available even when actionable buckets are empty', () {
    final nowLocal = DateTime(2026, 2, 24, 12, 0);
    final summary = TaskHubSummary.fromTodos(
      const <Todo>[
        Todo(
          id: 'done-only',
          title: 'Done only',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 100,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(summary.isEmpty, isTrue);
    expect(summary.doneCount, 1);
    expect(summary.doneTodos.map((todo) => todo.id), <String>['done-only']);
  });
}
