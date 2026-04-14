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
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
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
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
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

  test('snapshot keeps base ordering when AI enhancement is applied', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'due-today',
          title: 'Reply today',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .add(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'backlog',
          title: 'Quarterly planning',
          updatedAtMs: 20,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'backlog',
            semanticAdjustment: 40,
            reason: 'Strategically important.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
          ),
        ],
      ),
    );

    final enhancedBacklog = snapshot.activeEntries
        .firstWhere((entry) => entry.todo.id == 'backlog');

    expect(snapshot.hasAiEnhancement, isTrue);
    expect(snapshot.basePrimaryFocus?.todo.id, 'due-today');
    expect(snapshot.baseSnapshot.primaryFocus?.todo.id, 'due-today');
    expect(snapshot.baseSnapshot.hasAiEnhancement, isFalse);
    expect(snapshot.baseActiveEntries.first.todo.id, 'due-today');
    expect(snapshot.primaryFocus?.todo.id, 'due-today');
    expect(enhancedBacklog.reasonText, 'Strategically important.');
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

  test('in-progress status alone does not hard-guard priority', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'status-only',
          title: 'Keep moving',
          updatedAtMs: 10,
          status: 'in_progress',
        ),
        todo(
          id: 'neutral',
          title: 'Neutral task',
          updatedAtMs: 20,
        ),
      ],
      nowLocal: nowLocal,
    );

    final inProgressEntry = snapshot.allEntries
        .firstWhere((entry) => entry.todo.id == 'status-only');
    expect(inProgressEntry.hasHardFocusGuard, isFalse);
    expect(snapshot.primaryFocus?.todo.id, 'neutral');
  });

  test('manual urgency does not outrank a due-today hard guard', () {
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
          manualUrgencyNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.primaryFocus?.todo.id, 'due-today');
  });

  test('pure move-up intent only advances one slot after ai rerank', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'top', title: 'Top task', updatedAtMs: 30),
        todo(id: 'middle', title: 'Middle task', updatedAtMs: 20),
        todo(
          id: 'raised',
          title: 'Raised task',
          updatedAtMs: 10,
          manualImportanceNudgeScore: 2,
          manualUrgencyNudgeScore: 2,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'top',
            semanticAdjustment: 40,
            reason: 'AI keeps this first.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    expect(
      snapshot.activeEntries.map((entry) => entry.todo.id).toList(),
      <String>['top', 'raised', 'middle'],
    );
  });

  test('pure move-up intent cannot jump past a hard guard', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'guarded',
          title: 'Due today',
          updatedAtMs: 30,
          dueAtMs: nowLocal
              .add(const Duration(hours: 2))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'raised',
          title: 'Raised task',
          updatedAtMs: 10,
          manualImportanceNudgeScore: 2,
          manualUrgencyNudgeScore: 2,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(
      snapshot.activeEntries.map((entry) => entry.todo.id).toList(),
      <String>['guarded', 'raised'],
    );
  });

  test('base primary focus keeps pre-move order when a task is manually raised',
      () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'top', title: 'Top task', updatedAtMs: 30),
        todo(
          id: 'raised',
          title: 'Raised task',
          updatedAtMs: 10,
          manualImportanceNudgeScore: 2,
          manualUrgencyNudgeScore: 2,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.primaryFocus?.todo.id, 'raised');
    expect(snapshot.basePrimaryFocus?.todo.id, 'top');
    expect(snapshot.baseSnapshot.primaryFocus?.todo.id, 'top');
  });

  test('legacy importance-only signal does not gain extra one-slot move bias',
      () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'scheduled-top',
          title: 'Scheduled top',
          updatedAtMs: 30,
          dueAtMs: nowLocal
              .add(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'legacy-important',
          title: 'Legacy importance-only task',
          updatedAtMs: 20,
          manualImportanceNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(
      snapshot.activeEntries.map((entry) => entry.todo.id).toList(),
      <String>['scheduled-top', 'legacy-important'],
    );
  });

  test('legacy large urgency signal keeps score semantics', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'neutral-top', title: 'Neutral top', updatedAtMs: 30),
        todo(
          id: 'legacy-up',
          title: 'Legacy urgency +2',
          updatedAtMs: 20,
          manualUrgencyNudgeScore: 2,
        ),
        todo(id: 'neutral-bottom', title: 'Neutral bottom', updatedAtMs: 10),
      ],
      nowLocal: nowLocal,
    );

    expect(
      snapshot.activeEntries.map((entry) => entry.todo.id).toList(),
      <String>['legacy-up', 'neutral-top', 'neutral-bottom'],
    );
  });

  test('legacy urgency +1 keeps score semantics instead of one-slot move', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'neutral-top', title: 'Neutral top', updatedAtMs: 40),
        todo(id: 'neutral-mid', title: 'Neutral mid', updatedAtMs: 30),
        todo(id: 'neutral-low', title: 'Neutral low', updatedAtMs: 20),
        todo(
          id: 'legacy-up',
          title: 'Legacy urgency +1',
          updatedAtMs: 10,
          manualUrgencyNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(
      snapshot.activeEntries.map((entry) => entry.todo.id).toList(),
      <String>['legacy-up', 'neutral-top', 'neutral-mid', 'neutral-low'],
    );
  });

  test('negative urgency score sinks task below neutral peer', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'sunk',
          title: 'Ignore this for now',
          updatedAtMs: 10,
          manualUrgencyNudgeScore: -1,
        ),
        todo(
          id: 'neutral',
          title: 'Neutral task',
          updatedAtMs: 20,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.primaryFocus?.todo.id, 'neutral');
  });

  test('far-future scheduled task does not outrank important backlog task', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'far-future',
          title: 'Future commitment',
          updatedAtMs: 10,
          dueAtMs: nowLocal
              .add(const Duration(days: 30))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
        todo(
          id: 'important-backlog',
          title: 'Important backlog',
          updatedAtMs: 20,
          manualImportanceNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.primaryFocus?.todo.id, 'important-backlog');
  });

  test('manual importance breaks ties after effective urgency', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(id: 'neutral', title: 'Neutral task', updatedAtMs: 10),
        todo(
          id: 'important',
          title: 'Strategic task',
          updatedAtMs: 20,
          manualImportanceNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
    );

    expect(snapshot.primaryFocus?.todo.id, 'important');
  });

  test('important unscheduled tasks stay in next-up display bucket', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'primary',
          title: 'Primary',
          updatedAtMs: 100,
          manualUrgencyNudgeScore: 1,
        ),
        todo(
          id: 'important',
          title: 'Strategic follow-up',
          updatedAtMs: 20,
          manualImportanceNudgeScore: 1,
        ),
        todo(id: 'backlog', title: 'Someday maybe', updatedAtMs: 10),
      ],
      nowLocal: nowLocal,
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

  test('legacy mixed signals keep score semantics without extra move-down bias',
      () {
    final nowLocal = DateTime(2026, 4, 8, 12, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'upload',
          title: 'Upload short video',
          updatedAtMs: 300,
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 2))
              .toUtc()
              .millisecondsSinceEpoch,
          manualUrgencyNudgeScore: -1,
        ),
        todo(
          id: 'suit',
          title: 'Wear suit today',
          updatedAtMs: 200,
          status: 'in_progress',
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 3))
              .toUtc()
              .millisecondsSinceEpoch,
          manualUrgencyNudgeScore: 1,
        ),
        todo(
          id: 'script',
          title: 'Make a Chinese short video',
          updatedAtMs: 100,
          dueAtMs: nowLocal
              .subtract(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          manualImportanceNudgeScore: -1,
          manualUrgencyNudgeScore: -1,
        ),
        todo(
          id: 'research',
          title: 'Research recent scripts',
          updatedAtMs: 80,
          status: 'in_progress',
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'upload',
            semanticAdjustment: 15,
            reason: 'Potential blocker.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ),
          TaskPriorityAiEntry(
            todoId: 'suit',
            semanticAdjustment: -1,
            reason: 'Personal reminder.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: false,
            isUrgent: true,
          ),
          TaskPriorityAiEntry(
            todoId: 'script',
            semanticAdjustment: 2,
            reason: 'Core creative task.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ),
          TaskPriorityAiEntry(
            todoId: 'research',
            semanticAdjustment: 1,
            reason: 'Important preparation task.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 'suit');
    expect(snapshot.nextUpEntries.map((entry) => entry.todo.id).take(3), [
      'research',
      'upload',
      'script',
    ]);
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
    expect(
      snapshot.allEntries
          .firstWhere((entry) => entry.todo.id == 'noisy')
          .reasonText,
      isNull,
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
