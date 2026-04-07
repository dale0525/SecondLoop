import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_resolution_controller.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';

void main() {
  test('same refresh generation from an older action does not clear newer one',
      () {
    final controller = TaskHubPriorityResolutionController();
    final baseline = DateTime(2026, 4, 8, 10);

    controller.startAction(
      todoId: 'first',
      baselineComputedAtLocal: DateTime(2026, 4, 8, 9),
      baselineResolutionPhase: TaskPriorityResolutionPhase.localPublished,
      baselineRefreshGeneration: 1,
    );
    controller.consumeSnapshot(
      const TaskPrioritySnapshot.empty().copyWith(
        computedAtLocal: DateTime(2026, 4, 8, 9, 1),
        resolutionPhase: TaskPriorityResolutionPhase.awaitingAi,
        refreshGeneration: 1,
      ),
    );

    controller.startAction(
      todoId: 'second',
      baselineComputedAtLocal: baseline,
      baselineResolutionPhase: TaskPriorityResolutionPhase.awaitingAi,
      baselineRefreshGeneration: 2,
    );
    controller.consumeSnapshot(
      const TaskPrioritySnapshot.empty().copyWith(
        computedAtLocal: baseline,
        resolutionPhase: TaskPriorityResolutionPhase.aiResolved,
        refreshGeneration: 2,
      ),
    );

    expect(controller.state.todoId, 'second');
    expect(
      controller.state.status,
      TaskHubPriorityResolutionStatus.awaitingLocalFeedback,
    );
  });

  test('newer refresh generation transitions a pending action', () {
    final controller = TaskHubPriorityResolutionController();
    final baseline = DateTime(2026, 4, 8, 10);

    controller.startAction(
      todoId: 'second',
      baselineComputedAtLocal: baseline,
      baselineResolutionPhase: TaskPriorityResolutionPhase.awaitingAi,
      baselineRefreshGeneration: 2,
    );
    controller.consumeSnapshot(
      const TaskPrioritySnapshot.empty().copyWith(
        computedAtLocal: DateTime(2026, 4, 8, 10, 1),
        resolutionPhase: TaskPriorityResolutionPhase.awaitingAi,
        refreshGeneration: 3,
      ),
    );

    expect(controller.pendingTodoId, 'second');
    expect(
      controller.state.status,
      TaskHubPriorityResolutionStatus.awaitingAiResolution,
    );
  });
}
