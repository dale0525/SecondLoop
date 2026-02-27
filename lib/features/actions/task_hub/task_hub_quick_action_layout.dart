import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import 'task_hub_quick_actions.dart';

enum TaskHubQuickActionSectionKind {
  scheduled,
  dueReview,
  unscheduled,
  done,
}

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
  required Todo todo,
  required TaskHubQuickActionSectionKind sectionKind,
  DateTime? dueAtLocal,
}) {
  final actions = context.t.actions.taskHub.actions;
  final nowLocal = DateTime.now();
  final resolvedDueAtLocal = dueAtLocal ??
      (todo.dueAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              todo.dueAtMs!,
              isUtc: true,
            ).toLocal());

  final isDueToday = resolvedDueAtLocal != null &&
      resolvedDueAtLocal.year == nowLocal.year &&
      resolvedDueAtLocal.month == nowLocal.month &&
      resolvedDueAtLocal.day == nowLocal.day;
  final isOverdue =
      resolvedDueAtLocal != null && resolvedDueAtLocal.isBefore(nowLocal);
  final isFutureScheduled =
      resolvedDueAtLocal != null && !isOverdue && !isDueToday;

  TaskHubQuickActionItem chip(
    TaskHubQuickAction action, {
    required String label,
    required IconData icon,
    TaskHubQuickActionTone tone = TaskHubQuickActionTone.secondary,
  }) =>
      TaskHubQuickActionItem(
        action: action,
        label: label,
        icon: icon,
        tone: tone,
      );

  if (sectionKind == TaskHubQuickActionSectionKind.done) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.reopen,
          label: actions.reopen,
          icon: Icons.undo_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.redo,
          label: actions.redo,
          icon: Icons.replay_rounded,
        ),
      ],
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.dismiss,
          label: context.t.common.actions.delete,
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
  }

  if (todo.status == 'in_progress') {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.done,
          label: actions.done,
          icon: Icons.check_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.pauseTomorrow,
          label: actions.pauseTomorrow,
          icon: Icons.pause_circle_outline_rounded,
        ),
      ],
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.thisWeek,
          label: actions.thisWeek,
          icon: Icons.date_range_rounded,
        ),
        chip(
          TaskHubQuickAction.moveToInbox,
          label: actions.moveToInbox,
          icon: Icons.inbox_rounded,
        ),
      ],
    );
  }

  if (sectionKind == TaskHubQuickActionSectionKind.dueReview) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.today,
          label: actions.todayProcess,
          icon: Icons.today_rounded,
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
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.thisWeek,
          label: actions.thisWeek,
          icon: Icons.date_range_rounded,
        ),
      ],
    );
  }

  if (sectionKind == TaskHubQuickActionSectionKind.unscheduled) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.today,
          label: actions.today,
          icon: Icons.today_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.tomorrow,
          label: actions.tomorrow,
          icon: Icons.event_rounded,
        ),
      ],
      <TaskHubQuickActionItem>[
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
        chip(
          TaskHubQuickAction.dismiss,
          label: context.t.common.actions.delete,
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
  }

  if (isOverdue || isDueToday) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.done,
          label: actions.done,
          icon: Icons.check_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.tonight,
          label: actions.tonight,
          icon: Icons.bedtime_rounded,
        ),
      ],
      <TaskHubQuickActionItem>[
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
      ],
    );
  }

  if (isFutureScheduled) {
    return (
      <TaskHubQuickActionItem>[
        chip(
          TaskHubQuickAction.start,
          label: actions.start,
          icon: Icons.play_arrow_rounded,
          tone: TaskHubQuickActionTone.primary,
        ),
        chip(
          TaskHubQuickAction.done,
          label: actions.done,
          icon: Icons.check_rounded,
        ),
      ],
      <TaskHubQuickActionItem>[
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
      ],
    );
  }

  return (
    <TaskHubQuickActionItem>[
      chip(
        TaskHubQuickAction.today,
        label: actions.today,
        icon: Icons.today_rounded,
        tone: TaskHubQuickActionTone.primary,
      ),
      chip(
        TaskHubQuickAction.tomorrow,
        label: actions.tomorrow,
        icon: Icons.event_rounded,
      ),
    ],
    <TaskHubQuickActionItem>[
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
      chip(
        TaskHubQuickAction.done,
        label: actions.done,
        icon: Icons.check_rounded,
      ),
    ],
  );
}
