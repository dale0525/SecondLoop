import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_guards.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  test('shared helper marks in-progress todo as hard focus guarded', () {
    final guarded = hasTaskPriorityHardGuardForTodo(
      todo(id: 'a', title: 'Ship it', updatedAtMs: 10, status: 'in_progress'),
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    expect(guarded, isTrue);
  });

  test('entry hard focus getter delegates to shared helper semantics', () {
    final entry = TaskPriorityEntry(
      todo: todo(id: 'b', title: 'Today', updatedAtMs: 10),
      band: TaskPriorityBand.focus,
      ruleScore: 1,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[TaskPriorityReasonKind.dueToday],
      suggestedAction: TaskPrioritySuggestionKind.doNow,
      isDueToday: true,
    );

    expect(entry.hasHardFocusGuard, isTrue);
    expect(
      hasTaskPriorityHardGuard(
        isOverdue: entry.isOverdue,
        isDueToday: entry.isDueToday,
        isInProgress: entry.isInProgress,
      ),
      isTrue,
    );
  });

  test('future scheduled todo is not hard focus guarded', () {
    final now = DateTime(2026, 3, 13, 10, 0);
    final guarded = hasTaskPriorityHardGuardForTodo(
      todo(
        id: 'c',
        title: 'Later',
        updatedAtMs: 10,
        dueAtMs:
            now.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
      ),
      nowLocal: now,
    );

    expect(guarded, isFalse);
  });
}
