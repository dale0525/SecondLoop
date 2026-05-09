import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';

void main() {
  test('converts runtime plan drafts without legacy digest semantics', () {
    final controller = SecretaryController(
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );

    final plan = controller.planFromRuntimeDraft(
      const SecretaryRuntimePlanDraft(
        id: 'runtime-plan-1',
        title: 'Runtime daily plan',
        generatedAtMs: 1700000000000,
        items: [
          SecretaryRuntimePlanItem(
            id: 'runtime-item-1',
            taskId: 'task-1',
            title: 'Submit review',
            status: 'open',
            requiresConfirmation: true,
          ),
        ],
      ),
    );

    expect(plan.id, 'runtime-plan-1');
    expect(plan.route, 'cloud_runtime');
    expect(plan.generatedBy, 'cloud_runtime');
    expect(plan.digestGeneratedAtMs, isNull);
    expect(plan.sections.focus.single.todoId, 'task-1');
    expect(plan.sections.focus.single.reason, 'open');
    expect(plan.sections.focus.single.requiresConfirmation, isTrue);
  });
}
