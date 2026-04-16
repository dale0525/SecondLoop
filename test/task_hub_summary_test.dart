import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_summary.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('summary derives focus open and done buckets', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        Todo(
          id: 'overdue',
          title: 'Overdue',
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
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
          title: 'Scheduled',
          dueAtMs: nowLocal
              .add(const Duration(days: 1))
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
        Todo(
          id: 'review',
          title: 'Review',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'done',
          title: 'Done',
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
      nowLocal: nowLocal,
      checklistProgress: const <TodoChecklistProgress>[
        TodoChecklistProgress(todoId: 'overdue', totalCount: 3, doneCount: 1),
      ],
    );

    expect(summary.dueCount, 1);
    expect(summary.overdueCount, 1);
    expect(summary.upcomingCount, 2);
    expect(summary.reviewCount, 1);
    expect(summary.backlogCount, 0);
    expect(summary.doneCount, 1);
    expect(summary.snapshot.primaryFocus?.todo.id, 'overdue');
    expect(summary.checklistProgressByTodoId['overdue']?.doneCount, 1);
    expect(summary.checklistProgressByTodoId['overdue']?.totalCount, 3);
  });

  test('summary collapses unfinished counts into one open-task bucket', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final summary = TaskHubSummary.fromTodos(
      <Todo>[
        Todo(
          id: 'focus',
          title: 'Focus',
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'scheduled',
          title: 'Scheduled',
          dueAtMs: nowLocal
              .add(const Duration(days: 1))
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
          id: 'backlog',
          title: 'Backlog',
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
    );

    expect(summary.snapshot.primaryFocus?.todo.id, 'focus');
    expect(summary.upcomingCount, 2);
    expect(summary.backlogCount, 0);
    expect(
      summary.upcomingTodos.map((todo) => todo.id),
      <String>['scheduled', 'backlog'],
    );
    expect(summary.backlogTodos, isEmpty);
  });

  test(
      'summary open preview excludes the selected focus while due list stays intact',
      () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        const Todo(
          id: 'important',
          title: 'Important roadmap',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
        ),
        Todo(
          id: 'scheduled',
          title: 'Scheduled follow-up',
          dueAtMs: nowLocal
              .add(const Duration(days: 2))
              .toUtc()
              .millisecondsSinceEpoch,
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
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'important');
    expect(summary.upcomingPreviewTodos.first.id, 'scheduled');
    expect(summary.dueCount, 0);
    expect(summary.dueTodos, isEmpty);
  });

  test('summary open preview contains only non-focus tasks', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        Todo(
          id: 'scheduled-primary',
          title: 'Scheduled primary',
          dueAtMs: nowLocal
              .add(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
        ),
        Todo(
          id: 'scheduled-secondary',
          title: 'Scheduled secondary',
          dueAtMs: nowLocal
              .add(const Duration(days: 2))
              .toUtc()
              .millisecondsSinceEpoch,
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
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'scheduled-primary');
    expect(
      summary.upcomingPreviewTodos.map((todo) => todo.id),
      <String>['scheduled-secondary'],
    );
  });

  test('summary unified open bucket excludes the selected focus', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        Todo(
          id: 'review-primary',
          title: 'Reply now',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
        const Todo(
          id: 'backlog-secondary',
          title: 'Plan later',
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
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'review-primary');
    expect(summary.reviewCount, 1);
    expect(summary.backlogCount, 0);
    expect(
      summary.reviewTodos.map((todo) => todo.id),
      <String>['review-primary'],
    );
    expect(summary.backlogTodos, isEmpty);
    expect(
      summary.upcomingPreviewTodos.map((todo) => todo.id),
      <String>['backlog-secondary'],
    );
    expect(summary.backlogPreviewTodos, isEmpty);
  });

  test('summary open bucket is empty when only primary focus exists', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        const Todo(
          id: 'important-only',
          title: 'Important only',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'important-only');
    expect(summary.isEmpty, isTrue);
    expect(summary.upcomingCount, 0);
    expect(summary.upcomingTodos, isEmpty);
    expect(summary.upcomingPreviewTodos, isEmpty);
  });

  test('summary backlog preview stays empty for review-only tasks', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        Todo(
          id: 'review-only',
          title: 'Review only',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.reviewCount, 1);
    expect(summary.backlogCount, 0);
    expect(summary.backlogPreviewTodos, isEmpty);
  });

  test('summary backlog preview excludes non-primary review tasks', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        const Todo(
          id: 'primary-focus',
          title: 'Primary focus',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 100,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
        Todo(
          id: 'review-secondary',
          title: 'Review secondary',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 50,
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .millisecondsSinceEpoch,
          lastReviewAtMs: null,
        ),
      ],
      nowLocal: nowLocal,
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.reviewCount, 1);
    expect(summary.backlogCount, 0);
    expect(summary.backlogPreviewTodos, isEmpty);
  });

  test('done-only summary stays empty but preserves done list', () {
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
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    expect(summary.isEmpty, isTrue);
    expect(summary.doneTodos.map((todo) => todo.id), <String>['done-only']);
  });
}
