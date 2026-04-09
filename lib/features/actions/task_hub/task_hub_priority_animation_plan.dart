import 'dart:ui';

import 'task_priority_models.dart';

enum TaskHubPriorityAnimationSection {
  focus,
  nextUp,
  backlog,
  done,
}

enum TaskHubPriorityAnimationKind {
  none,
  sameSectionReorder,
  crossSectionMove,
  visibleInsertion,
  visibleRemoval,
  noEmphasis,
}

class TaskHubPriorityAnimationSnapshot {
  const TaskHubPriorityAnimationSnapshot({
    this.focusTodoId,
    this.nextUpTodoIds = const <String>[],
    this.backlogTodoIds = const <String>[],
    this.doneTodoIds = const <String>[],
  });

  factory TaskHubPriorityAnimationSnapshot.fromTaskPrioritySnapshot(
    TaskPrioritySnapshot snapshot, {
    int? doneVisibleCount,
  }) {
    final visibleDone = doneVisibleCount == null
        ? snapshot.done
        : snapshot.done.take(doneVisibleCount);
    return TaskHubPriorityAnimationSnapshot(
      focusTodoId: snapshot.primaryFocus?.todo.id,
      nextUpTodoIds: snapshot.nextUpEntries
          .map((entry) => entry.todo.id)
          .toList(growable: false),
      backlogTodoIds: snapshot.backlogEntries
          .map((entry) => entry.todo.id)
          .toList(growable: false),
      doneTodoIds:
          visibleDone.map((entry) => entry.todo.id).toList(growable: false),
    );
  }

  final String? focusTodoId;
  final List<String> nextUpTodoIds;
  final List<String> backlogTodoIds;
  final List<String> doneTodoIds;
}

class TaskHubPriorityAnimationPlan {
  const TaskHubPriorityAnimationPlan({
    required this.kind,
    required this.todoId,
    this.fromSection,
    this.toSection,
    this.fromIndex,
    this.toIndex,
  });

  const TaskHubPriorityAnimationPlan.none({required String todoId})
      : this(
          kind: TaskHubPriorityAnimationKind.none,
          todoId: todoId,
        );

  final TaskHubPriorityAnimationKind kind;
  final String todoId;
  final TaskHubPriorityAnimationSection? fromSection;
  final TaskHubPriorityAnimationSection? toSection;
  final int? fromIndex;
  final int? toIndex;
}

class TaskHubPriorityAnimationPosition {
  const TaskHubPriorityAnimationPosition({
    required this.section,
    required this.index,
  });

  final TaskHubPriorityAnimationSection section;
  final int index;
}

TaskHubPriorityAnimationPlan buildTaskHubPriorityAnimationPlan({
  required TaskHubPriorityAnimationSnapshot previous,
  required TaskHubPriorityAnimationSnapshot next,
  required String actedTodoId,
  required bool reducedMotion,
}) {
  final from = locateTaskHubPriorityVisibleEntry(previous, actedTodoId);
  final to = locateTaskHubPriorityVisibleEntry(next, actedTodoId);

  if (from == null && to == null) {
    return TaskHubPriorityAnimationPlan.none(todoId: actedTodoId);
  }
  if (reducedMotion) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.noEmphasis,
      todoId: actedTodoId,
      fromSection: from?.section,
      toSection: to?.section,
      fromIndex: from?.index,
      toIndex: to?.index,
    );
  }
  if (from != null && to == null) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.visibleRemoval,
      todoId: actedTodoId,
      fromSection: from.section,
      fromIndex: from.index,
    );
  }
  if (from == null && to != null) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.visibleInsertion,
      todoId: actedTodoId,
      toSection: to.section,
      toIndex: to.index,
    );
  }
  final fromPosition = from!;
  final toPosition = to!;
  if (fromPosition.section != toPosition.section) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.crossSectionMove,
      todoId: actedTodoId,
      fromSection: fromPosition.section,
      toSection: toPosition.section,
      fromIndex: fromPosition.index,
      toIndex: toPosition.index,
    );
  }
  if (fromPosition.index != toPosition.index) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.sameSectionReorder,
      todoId: actedTodoId,
      fromSection: fromPosition.section,
      toSection: toPosition.section,
      fromIndex: fromPosition.index,
      toIndex: toPosition.index,
    );
  }
  return TaskHubPriorityAnimationPlan.none(todoId: actedTodoId);
}

TaskHubPriorityAnimationPosition? locateTaskHubPriorityVisibleEntry(
  TaskHubPriorityAnimationSnapshot snapshot,
  String todoId,
) {
  if (snapshot.focusTodoId == todoId) {
    return const TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.focus,
      index: 0,
    );
  }
  final nextUpIndex = snapshot.nextUpTodoIds.indexOf(todoId);
  if (nextUpIndex != -1) {
    return TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.nextUp,
      index: nextUpIndex,
    );
  }
  final backlogIndex = snapshot.backlogTodoIds.indexOf(todoId);
  if (backlogIndex != -1) {
    return TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.backlog,
      index: backlogIndex,
    );
  }
  final doneIndex = snapshot.doneTodoIds.indexOf(todoId);
  if (doneIndex != -1) {
    return TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.done,
      index: doneIndex,
    );
  }
  return null;
}

Rect? resolveTaskHubPriorityFallbackRect({
  required TaskHubPriorityAnimationPlan plan,
  required Rect? sourceRect,
  TaskHubPriorityAnimationSection? sourceSection,
  int? sourceIndex,
}) {
  if (sourceRect == null) {
    return null;
  }
  switch (plan.kind) {
    case TaskHubPriorityAnimationKind.sameSectionReorder:
      final fromIndex = sourceIndex ?? plan.fromIndex ?? 0;
      final toIndex = plan.toIndex ?? plan.fromIndex ?? fromIndex;
      final delta = toIndex - fromIndex;
      if (delta == 0) {
        return sourceRect;
      }
      return sourceRect.shift(Offset(0, 28 * delta.sign.toDouble()));
    case TaskHubPriorityAnimationKind.crossSectionMove:
    case TaskHubPriorityAnimationKind.visibleInsertion:
    case TaskHubPriorityAnimationKind.visibleRemoval:
      final fromSection = sourceSection ?? plan.fromSection;
      final toSection = plan.toSection;
      final direction = _fallbackSectionDirection(
        kind: plan.kind,
        sourceSection: fromSection,
        targetSection: toSection,
      );
      if (direction == 0) {
        return null;
      }
      return sourceRect.shift(Offset(0, 32.0 * direction));
    case TaskHubPriorityAnimationKind.none:
    case TaskHubPriorityAnimationKind.noEmphasis:
      return null;
  }
}

int _fallbackSectionDirection({
  required TaskHubPriorityAnimationKind kind,
  required TaskHubPriorityAnimationSection? sourceSection,
  required TaskHubPriorityAnimationSection? targetSection,
}) {
  final fromOrder = sourceSection == null ? null : _sectionOrder(sourceSection);
  final toOrder = targetSection == null ? null : _sectionOrder(targetSection);
  if (fromOrder != null && toOrder != null) {
    final delta = toOrder - fromOrder;
    return delta == 0 ? 0 : delta.sign;
  }
  if (kind == TaskHubPriorityAnimationKind.visibleInsertion) {
    if (toOrder == null) return 0;
    if (fromOrder == null) {
      return toOrder <= _sectionOrder(TaskHubPriorityAnimationSection.nextUp)
          ? -1
          : 1;
    }
    final delta = toOrder - fromOrder;
    return delta == 0 ? 0 : delta.sign;
  }
  if (kind == TaskHubPriorityAnimationKind.visibleRemoval) {
    if (fromOrder == null) return 0;
    return fromOrder >= _sectionOrder(TaskHubPriorityAnimationSection.done)
        ? -1
        : 1;
  }
  return 0;
}

int _sectionOrder(TaskHubPriorityAnimationSection section) {
  return switch (section) {
    TaskHubPriorityAnimationSection.focus => 0,
    TaskHubPriorityAnimationSection.nextUp => 1,
    TaskHubPriorityAnimationSection.backlog => 2,
    TaskHubPriorityAnimationSection.done => 3,
  };
}
