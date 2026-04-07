import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_plan.dart';

void main() {
  test('planner returns sameSectionReorder for visible reorder', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a', 'b'],
      backlogTodoIds: <String>['c'],
      doneTodoIds: <String>['done'],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['b', 'a'],
      backlogTodoIds: <String>['c'],
      doneTodoIds: <String>['done'],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'a',
      reducedMotion: false,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.sameSectionReorder);
    expect(plan.fromSection, TaskHubPriorityAnimationSection.nextUp);
    expect(plan.toSection, TaskHubPriorityAnimationSection.nextUp);
    expect(plan.fromIndex, 0);
    expect(plan.toIndex, 1);
  });

  test('planner returns crossSectionMove for visible section change', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
      backlogTodoIds: <String>['b'],
      doneTodoIds: <String>[],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>[],
      backlogTodoIds: <String>['b'],
      doneTodoIds: <String>['a'],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'a',
      reducedMotion: false,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.crossSectionMove);
    expect(plan.fromSection, TaskHubPriorityAnimationSection.nextUp);
    expect(plan.toSection, TaskHubPriorityAnimationSection.done);
  });

  test('planner returns visibleRemoval when target is no longer visible', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>[],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>[],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>[],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'a',
      reducedMotion: false,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.visibleRemoval);
    expect(plan.fromSection, TaskHubPriorityAnimationSection.nextUp);
    expect(plan.toSection, isNull);
  });

  test('planner returns visibleInsertion when target becomes visible', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>['done'],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['redo-copy', 'a'],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>['done'],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'redo-copy',
      reducedMotion: false,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.visibleInsertion);
    expect(plan.fromSection, isNull);
    expect(plan.toSection, TaskHubPriorityAnimationSection.nextUp);
    expect(plan.fromIndex, isNull);
    expect(plan.toIndex, 0);
  });

  test('planner degrades when reduced motion is enabled', () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>[],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'a',
      nextUpTodoIds: <String>['focus'],
      backlogTodoIds: <String>[],
      doneTodoIds: <String>[],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'a',
      reducedMotion: true,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.noEmphasis);
  });
}
