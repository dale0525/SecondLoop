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
            semanticAdjustment: 8,
            reason: 'Strategically important.',
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

  test('manual urgency can outrank a due-today task', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'due-today',
          title: 'Due today',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .add(const Duration(hours: 3))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'backlog',
          title: 'Interrupt me first',
          updatedAtMs: 50,
        ),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'backlog': TaskPriorityManualSignal(urgencyScore: 4),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'backlog');
  });

  test('negative urgency score sinks task below neutral peer', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'sunk',
          title: 'Ignore this for now',
          updatedAtMs: 10,
        ),
        todo(
          id: 'neutral',
          title: 'Neutral task',
          updatedAtMs: 20,
        ),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'sunk': TaskPriorityManualSignal(urgencyScore: -1),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'neutral');
  });

  test('manual importance breaks ties after effective urgency', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'neutral', title: 'Neutral task', updatedAtMs: 10),
        todo(id: 'important', title: 'Strategic task', updatedAtMs: 20),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'important': TaskPriorityManualSignal(importanceScore: 3),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'important');
  });

  test('important unscheduled tasks stay in next-up display bucket', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'primary', title: 'Primary', updatedAtMs: 100),
        todo(id: 'important', title: 'Strategic follow-up', updatedAtMs: 20),
        todo(id: 'backlog', title: 'Someday maybe', updatedAtMs: 10),
      ],
      nowLocal: nowLocal,
      signalState: const TaskPriorityManualSignalState(
        byTodoId: <String, TaskPriorityManualSignal>{
          'primary': TaskPriorityManualSignal(urgencyScore: 3),
          'important': TaskPriorityManualSignal(importanceScore: 2),
        },
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'primary');
    expect(snapshot.nextUpEntries.map((entry) => entry.todo.id),
        <String>['important']);
    expect(snapshot.backlogEntries.map((entry) => entry.todo.id),
        <String>['backlog']);
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
            semanticAdjustment: 18,
            reason: 'This sounds strategically important.',
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
            semanticAdjustment: 999,
            reason: 'Maybe urgent, maybe important.',
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

  test('ai output only contributes per-item signals, not band or action', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'a', title: 'Clarify scope', updatedAtMs: 10),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'a',
            semanticAdjustment: 12,
            reason: 'Could be worth doing now.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    final entry = snapshot.allEntries.single;
    expect(entry.band, TaskPriorityBand.decide);
    expect(entry.suggestedAction, TaskPrioritySuggestionKind.schedule);
    expect(entry.semanticScore, 12);
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
            semanticAdjustment: 24,
            reason: 'It is blocking other planning work.',
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
