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
  if (entry.todo.status == 'in_progress') {
    return TaskHubQuickActionItem(
      action: TaskHubQuickAction.done,
      label: actions.done,
      icon: Icons.check_rounded,
      tone: TaskHubQuickActionTone.primary,
    );
  }
  return TaskHubQuickActionItem(
    action: TaskHubQuickAction.start,
    label: actions.start,
    icon: Icons.play_circle_outline_rounded,
    tone: TaskHubQuickActionTone.primary,
  );
}

TaskHubQuickActionItem? secondaryTaskHubQuickActionItemForEntry(
  BuildContext context, {
  required TaskPriorityEntry entry,
}) {
  final actions = context.t.actions.taskHub.actions;
  if (entry.todo.status == 'done') return null;
  return TaskHubQuickActionItem(
    action: TaskHubQuickAction.tomorrow,
    label: actions.tomorrow,
    icon: Icons.event_rounded,
    tone: TaskHubQuickActionTone.secondary,
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
  final timeAction = secondaryTaskHubQuickActionItemForEntry(
    context,
    entry: entry,
  );

  if (entry.todo.status == 'done') {
    return (
      <TaskHubQuickActionItem>[if (primaryAction != null) primaryAction],
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.redo,
          label: actions.redo,
          icon: Icons.replay_rounded,
        ),
        chip(
          TaskHubQuickAction.dismiss,
          label: context.t.common.actions.delete,
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
  }

  return (
    <TaskHubQuickActionItem>[
      if (primaryAction != null) primaryAction,
      if (timeAction != null) timeAction,
    ],
    <TaskHubQuickActionItem>[
      chip(
        TaskHubQuickAction.today,
        label: actions.today,
        icon: Icons.today_rounded,
      ),
    ],
  );
}
