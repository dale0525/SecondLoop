import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_controller.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_plan.dart';

void main() {
  test('stale completeAction does not override a newer animation', () {
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
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(10, 20, 120, 48),
    );
    final secondCapture = controller.beginAction(
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(40, 80, 120, 48),
    );

    controller.completeAction(
      secondCapture,
      animatedTodoId: 'a',
      next: next,
      targetRect: const Rect.fromLTWH(40, 280, 120, 48),
    );
    final currentOverlay = controller.activeOverlay!;

    controller.completeAction(
      firstCapture,
      animatedTodoId: 'a',
      next: next,
      targetRect: const Rect.fromLTWH(10, 220, 120, 48),
    );

    expect(controller.activeOverlay?.token, currentOverlay.token);
    expect(controller.activeOverlay?.beginRect, currentOverlay.beginRect);
    expect(controller.activeOverlay?.endRect, currentOverlay.endRect);
  });

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
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(10, 20, 120, 48),
    );
    controller.completeAction(
      firstCapture,
      animatedTodoId: 'a',
      next: next,
      targetRect: const Rect.fromLTWH(10, 220, 120, 48),
    );
    final firstOverlay = controller.activeOverlay!;

    final secondCapture = controller.beginAction(
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(10, 40, 120, 48),
    );
    controller.completeAction(
      secondCapture,
      animatedTodoId: 'a',
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

  test(
      'local confirmation keeps immediate feedback when reorder resolves to zero offset',
      () {
    const previous = TaskHubPriorityAnimationSnapshot(
      nextUpTodoIds: <String>['focus', 'a', 'b'],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      nextUpTodoIds: <String>['focus', 'b', 'a'],
    );
    final controller = TaskHubPriorityAnimationController();

    final capture = controller.beginAction(
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(0, 0, 100, 40),
    );
    final initialAnimation = controller.activeInlineAnimation;

    controller.completeAction(
      capture,
      animatedTodoId: 'a',
      next: next,
      targetRect: const Rect.fromLTWH(0, 0, 100, 40),
    );

    expect(controller.activeInlineAnimation, same(initialAnimation));
    expect(controller.activeInlineAnimation?.todoId, 'a');
    expect(
      controller.lastAnimationSource,
      TaskHubPriorityAnimationSource.localConfirmation,
    );
  });

  test(
      'local confirmation keeps immediate feedback when a secondary task becomes focus',
      () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a', 'b'],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'a',
      nextUpTodoIds: <String>['focus', 'b'],
    );
    final controller = TaskHubPriorityAnimationController();

    final capture = controller.beginAction(
      sourceTodoId: 'a',
      title: 'Task A',
      snapshot: previous,
      reducedMotion: false,
      sourceRect: const Rect.fromLTWH(0, 40, 100, 40),
    );
    final initialAnimation = controller.activeInlineAnimation;

    controller.completeAction(
      capture,
      animatedTodoId: 'a',
      next: next,
      targetRect: const Rect.fromLTWH(0, 0, 100, 40),
    );

    expect(controller.activeInlineAnimation, same(initialAnimation));
    expect(controller.activeOverlay, isNull);
    expect(
      controller.lastAnimationSource,
      TaskHubPriorityAnimationSource.localConfirmation,
    );
  });
}
