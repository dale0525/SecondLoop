import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/secretary/planning_review_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('planning review preserves priority snapshot order',
      (tester) async {
    final first = _entry(
      id: 'first',
      title: 'First from priority snapshot',
      isDueToday: true,
      reasonText: 'AI promoted this task.',
    );
    final second = _entry(
      id: 'second',
      title: 'Second even though overdue',
      isOverdue: true,
    );
    final snapshot = TaskPrioritySnapshot(
      source: TaskPrioritySnapshotSource.hybrid,
      focus: [second, first],
      scheduled: const <TaskPriorityEntry>[],
      decide: const <TaskPriorityEntry>[],
      done: const <TaskPriorityEntry>[],
      orderedActive: [first, second],
      computedAtLocal: DateTime(2026, 5, 4, 9),
    );
    final plan = RuleBasedPlanningEngine(
      nowLocal: () => DateTime(2026, 5, 4, 9),
    ).generateDailyPlanFromPrioritySnapshot(snapshot);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(home: PlanningReviewPage(plan: plan)),
      ),
    );

    final firstTop =
        tester.getTopLeft(find.text('First from priority snapshot')).dy;
    final secondTop =
        tester.getTopLeft(find.text('Second even though overdue')).dy;

    expect(firstTop, lessThan(secondTop));
    expect(find.text('AI promoted this task.'), findsOneWidget);
  });
}

TaskPriorityEntry _entry({
  required String id,
  required String title,
  bool isOverdue = false,
  bool isDueToday = false,
  String? reasonText,
}) {
  final now = DateTime(2026, 5, 4, 9).millisecondsSinceEpoch;
  return TaskPriorityEntry(
    todo: Todo(
      id: id,
      title: title,
      status: 'open',
      createdAtMs: platformIntFromInt(now),
      updatedAtMs: platformIntFromInt(now),
    ),
    band: TaskPriorityBand.focus,
    ruleScore: isOverdue ? 260 : 220,
    semanticScore: reasonText == null ? 0 : 100,
    reasons: const <TaskPriorityReasonKind>[],
    suggestedAction: TaskPrioritySuggestionKind.doNow,
    reasonText: reasonText,
    isOverdue: isOverdue,
    isDueToday: isDueToday,
  );
}
