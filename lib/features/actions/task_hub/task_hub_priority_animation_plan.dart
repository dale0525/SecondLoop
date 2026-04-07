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

TaskHubPriorityAnimationPlan buildTaskHubPriorityAnimationPlan({
  required TaskHubPriorityAnimationSnapshot previous,
  required TaskHubPriorityAnimationSnapshot next,
  required String actedTodoId,
  required bool reducedMotion,
}) {
  final from = _locateVisibleEntry(previous, actedTodoId);
  final to = _locateVisibleEntry(next, actedTodoId);

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
  if (from == null || to == null) {
    return TaskHubPriorityAnimationPlan.none(todoId: actedTodoId);
  }
  if (from.section != to.section) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.crossSectionMove,
      todoId: actedTodoId,
      fromSection: from.section,
      toSection: to.section,
      fromIndex: from.index,
      toIndex: to.index,
    );
  }
  if (from.index != to.index) {
    return TaskHubPriorityAnimationPlan(
      kind: TaskHubPriorityAnimationKind.sameSectionReorder,
      todoId: actedTodoId,
      fromSection: from.section,
      toSection: to.section,
      fromIndex: from.index,
      toIndex: to.index,
    );
  }
  return TaskHubPriorityAnimationPlan.none(todoId: actedTodoId);
}

class _TaskHubPriorityAnimationPosition {
  const _TaskHubPriorityAnimationPosition({
    required this.section,
    required this.index,
  });

  final TaskHubPriorityAnimationSection section;
  final int index;
}

_TaskHubPriorityAnimationPosition? _locateVisibleEntry(
  TaskHubPriorityAnimationSnapshot snapshot,
  String todoId,
) {
  if (snapshot.focusTodoId == todoId) {
    return const _TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.focus,
      index: 0,
    );
  }
  final nextUpIndex = snapshot.nextUpTodoIds.indexOf(todoId);
  if (nextUpIndex != -1) {
    return _TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.nextUp,
      index: nextUpIndex,
    );
  }
  final backlogIndex = snapshot.backlogTodoIds.indexOf(todoId);
  if (backlogIndex != -1) {
    return _TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.backlog,
      index: backlogIndex,
    );
  }
  final doneIndex = snapshot.doneTodoIds.indexOf(todoId);
  if (doneIndex != -1) {
    return _TaskHubPriorityAnimationPosition(
      section: TaskHubPriorityAnimationSection.done,
      index: doneIndex,
    );
  }
  return null;
}
