import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_feedback_store.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';

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

  test('overdue task outranks review due and future scheduled tasks', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'future-1',
          title: 'Future scheduled',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .add(const Duration(days: 2))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'review-1',
          title: 'Needs review',
          updatedAtMs: 20,
          status: 'inbox',
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'overdue-1',
          title: 'Overdue',
          updatedAtMs: 30,
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 3))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.focus.first.todo.id, 'overdue-1');
    expect(snapshot.scheduled.first.todo.id, 'future-1');
    expect(snapshot.decide.first.todo.id, 'review-1');
    expect(snapshot.source, TaskPrioritySnapshotSource.rules);
  });

  test('in progress and due today stay in focus', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'in-progress',
          title: 'Work in progress',
          updatedAtMs: 50,
          status: 'in_progress',
        ),
        todo(
          id: 'today',
          title: 'Due today',
          updatedAtMs: 40,
          dueAtMs: nowLocal
              .add(const Duration(hours: 2))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(
        snapshot.focus.map((entry) => entry.todo.id), contains('in-progress'));
    expect(snapshot.focus.map((entry) => entry.todo.id), contains('today'));
    expect(snapshot.primaryFocus?.todo.id, 'in-progress');
  });

  test('future scheduled and snoozed tasks do not leak into focus', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'future',
          title: 'Scheduled next week',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .add(const Duration(days: 7))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'snoozed',
          title: 'Snoozed review',
          updatedAtMs: 20,
          status: 'inbox',
          reviewStage: 2,
          nextReviewAtMs: nowLocal
              .add(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.focus, isEmpty);
    expect(
        snapshot.scheduled.map((entry) => entry.todo.id), <String>['future']);
    expect(snapshot.decide.map((entry) => entry.todo.id), <String>['snoozed']);
  });

  test('hybrid rerank keeps hard priority guards when confidence is low', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'overdue',
          title: 'Ship billing fix',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 5))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'clarify',
          title: 'Clarify plan',
          updatedAtMs: 20,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'clarify',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 18,
            reason: 'This sounds strategically important.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.low,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'overdue');
    expect(snapshot.focus.first.todo.id, 'overdue');
    expect(snapshot.source, TaskPrioritySnapshotSource.hybrid);
  });

  test('feedback suppression demotes AI-promoted tasks', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'a', title: 'Idea backlog', updatedAtMs: 10),
        todo(id: 'b', title: 'Clarify roadmap', updatedAtMs: 20),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'b',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 24,
            reason: 'It is blocking other planning work.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      feedbackState: const TaskPriorityFeedbackState(
        suppressedTodoIds: <String>{'b'},
        deprioritizedTodoIds: <String>{'b'},
      ),
    );

    expect(snapshot.focus, isEmpty);
    expect(snapshot.decide.first.todo.id, 'a');
  });
}
