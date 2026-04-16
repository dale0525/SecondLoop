import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_sticky_focus.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    int? dueAtMs,
    int? reviewStage,
    int? nextReviewAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: 'open',
      sourceEntryId: null,
      createdAtMs: platformIntFromInt(0),
      updatedAtMs: platformIntFromInt(1),
      reviewStage: reviewStage == null ? null : platformIntFromInt(reviewStage),
      nextReviewAtMs:
          nextReviewAtMs == null ? null : platformIntFromInt(nextReviewAtMs),
      lastReviewAtMs: null,
      manualImportanceNudgeScore: null,
      manualUrgencyNudgeScore: null,
    );
  }

  TaskPriorityEntry entry(Todo todo) {
    return TaskPriorityEntry(
      todo: todo,
      band: TaskPriorityBand.focus,
      ruleScore: 1,
      semanticScore: 0,
      reasons: const <TaskPriorityReasonKind>[TaskPriorityReasonKind.dueToday],
      suggestedAction: TaskPrioritySuggestionKind.doNow,
      isDueToday: true,
      dueDerivedUrgencyScore: 1,
    );
  }

  test('sticky focus remembers platform ints without json encoding errors', () {
    final state = TaskPriorityStickyFocusState();
    final nowLocal = DateTime(2026, 4, 15, 20);
    final focusEntry = entry(
      todo(
        id: 'focus',
        title: 'Review release checklist',
        dueAtMs: nowLocal.toUtc().millisecondsSinceEpoch,
        reviewStage: 2,
        nextReviewAtMs: nowLocal
            .add(const Duration(hours: 4))
            .toUtc()
            .millisecondsSinceEpoch,
      ),
    );
    final snapshot = TaskPrioritySnapshot(
      source: TaskPrioritySnapshotSource.rules,
      focus: <TaskPriorityEntry>[focusEntry],
      scheduled: const <TaskPriorityEntry>[],
      decide: const <TaskPriorityEntry>[],
      done: const <TaskPriorityEntry>[],
      orderedActive: <TaskPriorityEntry>[focusEntry],
      selectedFocusTodoId: focusEntry.todo.id,
      computedAtLocal: nowLocal,
    );

    expect(() => state.remember(snapshot, nowLocal), returnsNormally);
    expect(state.apply(snapshot, nowLocal: nowLocal).primaryFocus?.todo.id,
        'focus');
  });
}
