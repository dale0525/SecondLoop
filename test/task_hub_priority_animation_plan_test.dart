import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_plan.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/src/rust/db.dart';

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

  test('planner treats next-up to backlog reshuffle as same open-list reorder',
      () {
    const previous = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>['a'],
      backlogTodoIds: <String>['b'],
      doneTodoIds: <String>[],
    );
    const next = TaskHubPriorityAnimationSnapshot(
      focusTodoId: 'focus',
      nextUpTodoIds: <String>[],
      backlogTodoIds: <String>['b', 'a'],
      doneTodoIds: <String>[],
    );

    final plan = buildTaskHubPriorityAnimationPlan(
      previous: previous,
      next: next,
      actedTodoId: 'a',
      reducedMotion: false,
    );

    expect(plan.kind, TaskHubPriorityAnimationKind.sameSectionReorder);
    expect(plan.fromIndex, 0);
    expect(plan.toIndex, 1);
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

  test('visible entry lookup follows unified open-task order from snapshot',
      () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        Todo(
          id: 'focus',
          title: 'Current focus',
          dueAtMs: nowLocal
              .subtract(const Duration(hours: 1))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'scheduled',
          title: 'Scheduled task',
          dueAtMs: nowLocal
              .add(const Duration(days: 2))
              .toUtc()
              .millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'backlog',
          title: 'AI promoted backlog',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'backlog',
            semanticAdjustment: 120,
            reason: 'Promoted for this session.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    expect(
      snapshot.openEntries.map((entry) => entry.todo.id).toList(),
      <String>['backlog', 'scheduled'],
    );

    final visibleSnapshot =
        TaskHubPriorityAnimationSnapshot.fromTaskPrioritySnapshot(snapshot);
    final backlogPosition =
        locateTaskHubPriorityVisibleEntry(visibleSnapshot, 'backlog');
    final scheduledPosition =
        locateTaskHubPriorityVisibleEntry(visibleSnapshot, 'scheduled');

    expect(backlogPosition?.section, TaskHubPriorityAnimationSection.nextUp);
    expect(backlogPosition?.index, 0);
    expect(scheduledPosition?.section, TaskHubPriorityAnimationSection.nextUp);
    expect(scheduledPosition?.index, 1);
  });

  test('fallback rect moves downward when same-section target index increases',
      () {
    final rect = resolveTaskHubPriorityFallbackRect(
      plan: const TaskHubPriorityAnimationPlan(
        kind: TaskHubPriorityAnimationKind.sameSectionReorder,
        todoId: 'a',
        fromSection: TaskHubPriorityAnimationSection.nextUp,
        toSection: TaskHubPriorityAnimationSection.nextUp,
        fromIndex: 0,
        toIndex: 2,
      ),
      sourceRect: const Rect.fromLTWH(10, 20, 120, 48),
      sourceSection: TaskHubPriorityAnimationSection.nextUp,
      sourceIndex: 0,
    );

    expect(rect, isNotNull);
    expect(rect!.top, greaterThan(20));
  });

  test('fallback rect moves upward when done item reopens offscreen', () {
    final rect = resolveTaskHubPriorityFallbackRect(
      plan: const TaskHubPriorityAnimationPlan(
        kind: TaskHubPriorityAnimationKind.visibleRemoval,
        todoId: 'done',
        fromSection: TaskHubPriorityAnimationSection.done,
        fromIndex: 0,
      ),
      sourceRect: const Rect.fromLTWH(10, 220, 120, 48),
      sourceSection: TaskHubPriorityAnimationSection.done,
      sourceIndex: 0,
    );

    expect(rect, isNotNull);
    expect(rect!.top, lessThan(220));
  });

  test('fallback rect uses source section for offscreen redo insertion', () {
    final rect = resolveTaskHubPriorityFallbackRect(
      plan: const TaskHubPriorityAnimationPlan(
        kind: TaskHubPriorityAnimationKind.visibleInsertion,
        todoId: 'redo-copy',
        toSection: TaskHubPriorityAnimationSection.nextUp,
        toIndex: 0,
      ),
      sourceRect: const Rect.fromLTWH(10, 220, 120, 48),
      sourceSection: TaskHubPriorityAnimationSection.done,
      sourceIndex: 0,
    );

    expect(rect, isNotNull);
    expect(rect!.top, lessThan(220));
  });

  test('fallback rect treats backlog anchor as the same open-list direction',
      () {
    final rect = resolveTaskHubPriorityFallbackRect(
      plan: const TaskHubPriorityAnimationPlan(
        kind: TaskHubPriorityAnimationKind.sameSectionReorder,
        todoId: 'a',
        fromSection: TaskHubPriorityAnimationSection.nextUp,
        toSection: TaskHubPriorityAnimationSection.backlog,
        fromIndex: 0,
        toIndex: 1,
      ),
      sourceRect: const Rect.fromLTWH(10, 20, 120, 48),
      sourceSection: TaskHubPriorityAnimationSection.nextUp,
      sourceIndex: 0,
    );

    expect(rect, isNotNull);
    expect(rect!.top, greaterThan(20));
  });
}
