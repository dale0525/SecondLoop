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

  if (entry.band == TaskPriorityBand.done) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.reopen,
          label: actions.reopen,
          icon: Icons.undo_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
      ],
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

  final recommended = _recommendedActionForEntry(entry);
  final recommendedLabel = switch (entry.suggestedAction) {
    TaskPrioritySuggestionKind.doNow => actions.doNow,
    TaskPrioritySuggestionKind.schedule => actions.schedule,
    TaskPrioritySuggestionKind.defer => actions.defer,
    TaskPrioritySuggestionKind.clarify => actions.clarify,
  };
  final recommendedIcon = switch (entry.suggestedAction) {
    TaskPrioritySuggestionKind.doNow => Icons.play_circle_outline_rounded,
    TaskPrioritySuggestionKind.schedule => Icons.event_available_rounded,
    TaskPrioritySuggestionKind.defer => Icons.schedule_send_rounded,
    TaskPrioritySuggestionKind.clarify => Icons.rule_folder_outlined,
  };

  final secondary = <TaskHubQuickActionItem>[
    chip(
      TaskHubQuickAction.today,
      label: actions.today,
      icon: Icons.today_rounded,
    ),
    chip(
      TaskHubQuickAction.tomorrow,
      label: actions.tomorrow,
      icon: Icons.event_rounded,
    ),
    chip(
      TaskHubQuickAction.thisWeek,
      label: actions.thisWeek,
      icon: Icons.date_range_rounded,
    ),
    chip(
      TaskHubQuickAction.later,
      label: actions.later,
      icon: Icons.schedule_send_rounded,
    ),
  ];

  if (entry.isReviewDue || entry.band == TaskPriorityBand.decide) {
    secondary.add(
      chip(
        TaskHubQuickAction.moveToInbox,
        label: actions.moveToInbox,
        icon: Icons.inbox_rounded,
      ),
    );
  }
  if (!entry.isInProgress) {
    secondary.add(
      chip(
        TaskHubQuickAction.done,
        label: actions.done,
        icon: Icons.check_rounded,
      ),
    );
  }

  if (entry.isReviewDue) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          recommended,
          label: recommendedLabel,
          icon: recommendedIcon,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.later,
          label: actions.later,
          icon: Icons.schedule_send_rounded,
        ),
        chip(
          TaskHubQuickAction.done,
          label: actions.done,
          icon: Icons.check_rounded,
        ),
      ],
      secondary
          .where((item) =>
              item.action != TaskHubQuickAction.later &&
              item.action != TaskHubQuickAction.done)
          .toList(growable: false),
    );
  }

  return (
    <TaskHubQuickActionItem>[
      chip(
        recommended,
        label: recommendedLabel,
        icon: recommendedIcon,
        tone: TaskHubQuickActionTone.primary,
      ),
    ],
    secondary,
  );
}

TaskHubQuickAction _recommendedActionForEntry(TaskPriorityEntry entry) {
  return switch (entry.suggestedAction) {
    TaskPrioritySuggestionKind.doNow => entry.isInProgress
        ? TaskHubQuickAction.done
        : entry.isFutureScheduled
            ? TaskHubQuickAction.start
            : TaskHubQuickAction.today,
    TaskPrioritySuggestionKind.schedule => entry.isFutureScheduled
        ? TaskHubQuickAction.thisWeek
        : TaskHubQuickAction.tomorrow,
    TaskPrioritySuggestionKind.defer => entry.isInProgress
        ? TaskHubQuickAction.pauseTomorrow
        : TaskHubQuickAction.later,
    TaskPrioritySuggestionKind.clarify => entry.isReviewDue
        ? TaskHubQuickAction.moveToInbox
        : TaskHubQuickAction.today,
  };
}
