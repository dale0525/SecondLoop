import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

void main() {
  group('RuleBasedPlanningEngine', () {
    final now = DateTime(2026, 4, 29, 9);
    final engine = RuleBasedPlanningEngine(nowLocal: () => now);

    test('groups overdue and due-today todos into focus', () {
      final plan = engine.generateDailyPlan([
        _todo(
          id: 'overdue',
          title: 'Submit app review',
          dueAtMs:
              now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        ),
        _todo(
          id: 'today',
          title: 'Prepare meeting notes',
          dueAtMs: now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
        ),
      ]);

      expect(plan.sections.focus.map((item) => item.todoId), [
        'overdue',
        'today',
      ]);
      expect(plan.sections.focus.first.reason, contains('Overdue'));
      expect(plan.requiresConfirmationCount, 2);
    });

    test('groups tomorrow tasks into due soon', () {
      final plan = engine.generateDailyPlan([
        _todo(
          id: 'tomorrow',
          title: 'Publish beta notes',
          dueAtMs: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
      ]);

      expect(plan.sections.dueSoon.single.todoId, 'tomorrow');
      expect(plan.sections.focus, isEmpty);
    });

    test('groups stale and unscheduled tasks into decision sections', () {
      final plan = engine.generateDailyPlan([
        _todo(
          id: 'stale',
          title: 'Update biometrics plan',
          updatedAtMs:
              now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
        ),
        _todo(
          id: 'unscheduled',
          title: 'Define secretary MVP',
          updatedAtMs:
              now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
      ]);

      expect(plan.sections.needsDecision.single.todoId, 'stale');
      expect(plan.sections.missingNextAction.single.todoId, 'unscheduled');
    });

    test('empty input produces an empty local plan', () {
      final plan = engine.generateDailyPlan(const <Todo>[]);

      expect(plan.sections.isEmpty, isTrue);
      expect(plan.itemCount, 0);
      expect(plan.route, 'local_rules');
    });
  });
}

Todo _todo({
  required String id,
  required String title,
  String status = 'open',
  int? dueAtMs,
  int? updatedAtMs,
}) {
  final created = DateTime(2026, 4, 1).millisecondsSinceEpoch;
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
    status: status,
    createdAtMs: platformIntFromInt(created),
    updatedAtMs: platformIntFromInt(updatedAtMs ?? created),
  );
}
