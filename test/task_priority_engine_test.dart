import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_feedback_store.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';
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
    expect(snapshot.primaryFocus?.todo.id, 'overdue-1');
    expect(snapshot.source, TaskPrioritySnapshotSource.rules);
  });

  test('primary focus is selected from all unfinished entries', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'review',
          title: 'Reply today',
          updatedAtMs: 20,
          status: 'inbox',
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'plan',
          title: 'Quarterly planning',
          updatedAtMs: 30,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'plan',
            priorityBand: TaskPriorityAiBand.next,
            semanticAdjustment: 8,
            reason: 'Strategically important.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: false,
          ),
        ],
      ),
    );

    expect(snapshot.focus, isEmpty);
    expect(snapshot.primaryFocus?.todo.id, 'review');
  });

  test('manual importance override can surface a planned task as focus', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final tomorrow = nowLocal.add(const Duration(days: 2));
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'scheduled',
          title: 'Scheduled follow-up',
          updatedAtMs: 10,
          dueAtMs: tomorrow.toUtc().millisecondsSinceEpoch,
        ),
        todo(
          id: 'backlog',
          title: 'Important roadmap',
          updatedAtMs: 50,
        ),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'backlog': TaskPriorityManualSignal(isImportant: true),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'backlog');
  });

  test(
      'hard focus guards stay ahead even when another task becomes urgent and important',
      () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'overdue',
          title: 'Pay rent',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 2))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'strategic',
          title: 'Quarterly plan',
          updatedAtMs: 100,
        ),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'overdue': TaskPriorityManualSignal(
            isImportant: false,
            isUrgent: false,
          ),
          'strategic': TaskPriorityManualSignal(
            isImportant: true,
            isUrgent: true,
          ),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'overdue');
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
            isImportant: true,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'overdue');
    expect(snapshot.source, TaskPrioritySnapshotSource.hybrid);
  });

  test('low-confidence ai semantic score does not take over primary focus', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'steady',
          title: 'Steady backlog',
          updatedAtMs: 100,
        ),
        todo(
          id: 'noisy',
          title: 'Noisy backlog',
          updatedAtMs: 10,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'noisy',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 999,
            reason: 'Maybe urgent, maybe important.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.low,
            isImportant: true,
            isUrgent: true,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'steady');
    expect(
      snapshot.allEntries
          .firstWhere((entry) => entry.todo.id == 'noisy')
          .semanticScore,
      0,
    );
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
            isImportant: true,
            isUrgent: true,
          ),
        ],
      ),
      feedbackState: const TaskPriorityFeedbackState(
        suppressedTodoIds: <String>{'b'},
        deprioritizedTodoIds: <String>{'b'},
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'a');
  });
}
