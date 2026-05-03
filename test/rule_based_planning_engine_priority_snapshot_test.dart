import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  group('RuleBasedPlanningEngine priority snapshot input', () {
    final now = DateTime(2026, 5, 4, 9);
    final engine = RuleBasedPlanningEngine(nowLocal: () => now);

    test('focus order follows priority snapshot orderedActive', () {
      final lowRuleButFirst = _entry(
        id: 'first',
        title: 'First from AI priority',
        band: TaskPriorityBand.focus,
        ruleScore: 10,
        semanticScore: 200,
        reasonText: 'AI promoted because it blocks launch.',
        isDueToday: true,
      );
      final highRuleButSecond = _entry(
        id: 'second',
        title: 'Second from local due date',
        band: TaskPriorityBand.focus,
        ruleScore: 260,
        isOverdue: true,
      );
      final snapshot = TaskPrioritySnapshot(
        source: TaskPrioritySnapshotSource.hybrid,
        enhancementSource: TaskPriorityEnhancementSource.aiLive,
        focus: [highRuleButSecond, lowRuleButFirst],
        scheduled: const <TaskPriorityEntry>[],
        decide: const <TaskPriorityEntry>[],
        done: const <TaskPriorityEntry>[],
        orderedActive: [lowRuleButFirst, highRuleButSecond],
        computedAtLocal: now,
      );

      final plan = engine.generateDailyPlanFromPrioritySnapshot(snapshot);

      expect(plan.sections.focus.map((item) => item.todoId), [
        'first',
        'second',
      ]);
      expect(plan.sections.focus.first.reason,
          'AI promoted because it blocks launch.');
      expect(plan.route, 'local_rules');
    });

    test('keeps manual nudges and scheduled sections from priority entries',
        () {
      final nudged = _entry(
        id: 'nudged',
        title: 'Manually important work',
        band: TaskPriorityBand.decide,
        manualImportanceNudgeScore: 1,
      );
      final scheduled = _entry(
        id: 'scheduled',
        title: 'Scheduled review',
        band: TaskPriorityBand.scheduled,
        isFutureScheduled: true,
        dueAtMs: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      final snapshot = TaskPrioritySnapshot(
        source: TaskPrioritySnapshotSource.rules,
        focus: const <TaskPriorityEntry>[],
        scheduled: [scheduled],
        decide: [nudged],
        done: const <TaskPriorityEntry>[],
        orderedActive: [nudged, scheduled],
        computedAtLocal: now,
      );

      final plan = engine.generateDailyPlanFromPrioritySnapshot(snapshot);

      expect(plan.sections.needsDecision.single.todoId, 'nudged');
      expect(plan.sections.needsDecision.single.reason, contains('priority'));
      expect(plan.sections.dueSoon.single.todoId, 'scheduled');
    });

    test('empty snapshot produces empty plan', () {
      final plan = engine.generateDailyPlanFromPrioritySnapshot(
        const TaskPrioritySnapshot.empty(),
      );

      expect(plan.sections.isEmpty, isTrue);
      expect(plan.itemCount, 0);
    });
  });
}

TaskPriorityEntry _entry({
  required String id,
  required String title,
  required TaskPriorityBand band,
  double ruleScore = 80,
  double semanticScore = 0,
  String? reasonText,
  bool isReviewDue = false,
  bool isSnoozed = false,
  bool isOverdue = false,
  bool isDueToday = false,
  bool isFutureScheduled = false,
  int manualImportanceNudgeScore = 0,
  int manualUrgencyNudgeScore = 0,
  int? dueAtMs,
}) {
  final now = DateTime(2026, 5, 4, 9).millisecondsSinceEpoch;
  return TaskPriorityEntry(
    todo: Todo(
      id: id,
      title: title,
      status: 'open',
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      createdAtMs: platformIntFromInt(now),
      updatedAtMs: platformIntFromInt(now),
      manualImportanceNudgeScore:
          platformIntFromInt(manualImportanceNudgeScore),
      manualUrgencyNudgeScore: platformIntFromInt(manualUrgencyNudgeScore),
    ),
    band: band,
    ruleScore: ruleScore,
    semanticScore: semanticScore,
    reasons: const <TaskPriorityReasonKind>[],
    suggestedAction: TaskPrioritySuggestionKind.doNow,
    reasonText: reasonText,
    isReviewDue: isReviewDue,
    isSnoozed: isSnoozed,
    isOverdue: isOverdue,
    isDueToday: isDueToday,
    isFutureScheduled: isFutureScheduled,
    manualImportanceNudgeScore: manualImportanceNudgeScore,
    manualUrgencyNudgeScore: manualUrgencyNudgeScore,
  );
}
