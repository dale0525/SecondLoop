import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_controller.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_plan.dart';

void main() {
  test('stale overlay completion does not clear a newer animation', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      doneTodoIds: <String>['a'],
    );
    final controller = TaskHubPriorityAnimationController();

    final firstCapture = controller.beginAction(
      todoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(10, 20, 120, 48),
    );
    controller.completeAction(
      firstCapture,
      next: next,
      targetRect: const Rect.fromLTWH(10, 220, 120, 48),
    );
    final firstOverlay = controller.activeOverlay!;

    final secondCapture = controller.beginAction(
      todoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(10, 40, 120, 48),
    );
    controller.completeAction(
      secondCapture,
      next: next,
      targetRect: const Rect.fromLTWH(10, 260, 120, 48),
    );
    final secondOverlay = controller.activeOverlay!;

    expect(secondOverlay.token, isNot(firstOverlay.token));

    controller.clearOverlay(firstOverlay.todoId, firstOverlay.token);
    expect(controller.activeOverlay?.token, secondOverlay.token);

    controller.clearOverlay(secondOverlay.todoId, secondOverlay.token);
    expect(controller.activeOverlay, isNull);
  });
}
