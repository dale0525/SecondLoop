import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_models.dart';

enum TaskHubQuickActionTone {
  primary,
  secondary,
}

class TaskHubQuickActionItem {
  const TaskHubQuickActionItem({
    required this.action,
    required this.label,
    required this.icon,
    this.tone = TaskHubQuickActionTone.secondary,
  });

  final TaskHubQuickAction action;
  final String label;
  final IconData icon;
  final TaskHubQuickActionTone tone;
}

typedef TaskHubQuickActionLayout = (
  List<TaskHubQuickActionItem>,
  List<TaskHubQuickActionItem>
);

TaskHubQuickActionItem? primaryTaskHubQuickActionItemForEntry(
  BuildContext context, {
  required TaskPriorityEntry entry,
}) {
  final actions = context.t.actions.taskHub.actions;
  if (entry.todo.status == 'done') {
    return TaskHubQuickActionItem(
      action: TaskHubQuickAction.reopen,
      label: actions.reopen,
      icon: Icons.undo_rounded,
      tone: TaskHubQuickActionTone.primary,
    );
  }

  if (!entry.isUrgent) {
    return TaskHubQuickActionItem(
      action: TaskHubQuickAction.increaseUrgency,
      label: actions.increaseUrgency,
      icon: Icons.priority_high_rounded,
      tone: TaskHubQuickActionTone.primary,
    );
  }
  if (!entry.isImportant) {
    return TaskHubQuickActionItem(
      action: TaskHubQuickAction.increaseImportance,
      label: actions.increaseImportance,
      icon: Icons.keyboard_double_arrow_up_rounded,
      tone: TaskHubQuickActionTone.primary,
    );
  }
  return TaskHubQuickActionItem(
    action: TaskHubQuickAction.done,
    label: actions.done,
    icon: Icons.check_rounded,
    tone: TaskHubQuickActionTone.primary,
  );
}

TaskHubQuickActionLayout buildTaskHubQuickActionLayout(
  BuildContext context, {
  required TaskPriorityEntry entry,
}) {
  final actions = context.t.actions.taskHub.actions;

  TaskHubQuickActionItem chip(
    TaskHubQuickAction action, {
    required String label,
    required IconData icon,
    TaskHubQuickActionTone tone = TaskHubQuickActionTone.secondary,
  }) {
    return TaskHubQuickActionItem(
      action: action,
      label: label,
      icon: icon,
      tone: tone,
    );
  }

  final primaryAction = primaryTaskHubQuickActionItemForEntry(
    context,
    entry: entry,
  );
  if (entry.todo.status == 'done') {
    return (
      <TaskHubQuickActionItem>[if (primaryAction != null) primaryAction],
      const <TaskHubQuickActionItem>[],
    );
  }

  final secondary = <TaskHubQuickActionItem>[
    chip(
      TaskHubQuickAction.increaseUrgency,
      label: actions.increaseUrgency,
      icon: Icons.priority_high_rounded,
    ),
    chip(
      TaskHubQuickAction.decreaseUrgency,
      label: actions.decreaseUrgency,
      icon: Icons.low_priority_rounded,
    ),
    chip(
      TaskHubQuickAction.increaseImportance,
      label: actions.increaseImportance,
      icon: Icons.keyboard_double_arrow_up_rounded,
    ),
    chip(
      TaskHubQuickAction.decreaseImportance,
      label: actions.decreaseImportance,
      icon: Icons.keyboard_double_arrow_down_rounded,
    ),
    chip(
      TaskHubQuickAction.done,
      label: actions.done,
      icon: Icons.check_rounded,
    ),
  ]
      .where((item) => item.action != primaryAction?.action)
      .toList(growable: false);

  return (
    <TaskHubQuickActionItem>[if (primaryAction != null) primaryAction],
    secondary,
  );
}
