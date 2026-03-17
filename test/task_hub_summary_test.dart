import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_summary.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('summary derives focus scheduled decide and done buckets', () {
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
    expect(summary.upcomingCount, 1);
    expect(summary.dueReviewCount, 1);
    expect(summary.doneCount, 1);
    expect(summary.snapshot.primaryFocus?.todo.id, 'overdue');
    expect(summary.checklistProgressByTodoId['overdue']?.doneCount, 1);
    expect(summary.checklistProgressByTodoId['overdue']?.totalCount, 3);
  });

  test(
      'summary preview includes globally selected focus without changing due list',
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
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'important': TaskPriorityManualSignal(isImportant: true),
        },
      ),
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'important');
    expect(summary.scheduledPreviewTodos.first.id, 'important');
    expect(summary.dueCount, 0);
    expect(summary.dueTodos, isEmpty);
  });

  test('summary preview does not duplicate selected focus from scheduled list',
      () {
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
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'scheduled-primary': TaskPriorityManualSignal(isImportant: true),
        },
      ),
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'scheduled-primary');
    expect(
      summary.scheduledPreviewTodos.map((todo) => todo.id),
      <String>['scheduled-primary', 'scheduled-secondary'],
    );
  });

  test('summary preview does not duplicate selected focus from decide list',
      () {
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
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'review-primary': TaskPriorityManualSignal(
            isImportant: true,
            isUrgent: true,
          ),
        },
      ),
    );

    final summary = TaskHubSummary.fromSnapshot(snapshot);

    expect(summary.snapshot.primaryFocus?.todo.id, 'review-primary');
    expect(
      summary.scheduledPreviewTodos.map((todo) => todo.id),
      <String>['review-primary'],
    );
    expect(
      summary.unscheduledPreviewTodos.map((todo) => todo.id),
      isNot(contains('review-primary')),
    );
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
