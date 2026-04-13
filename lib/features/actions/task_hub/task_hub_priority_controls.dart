import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

Widget buildTaskHubPriorityControls(
  BuildContext context, {
  required TaskPriorityEntry entry,
  required ValueChanged<TaskHubQuickAction> onQuickAction,
  required bool showPriorityControls,
  bool compactActions = false,
}) {
  final layout = buildTaskHubQuickActionLayout(context, entry: entry);
  final visibleActions =
      compactActions ? layout.$1.take(1).toList(growable: false) : layout.$1;
  final overflowActions = compactActions
      ? <TaskHubQuickActionItem>[
          ...layout.$1.skip(1),
          ...layout.$2,
        ]
      : layout.$2;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final action in visibleActions)
            _TaskHubQuickButton(
              key: ValueKey(
                'task_hub_page_quick_${entry.todo.id}_${action.action.name}',
              ),
              label: action.label,
              icon: action.icon,
              tone: action.tone,
              onPressed: () => onQuickAction(action.action),
            ),
          if (overflowActions.isNotEmpty)
            _TaskHubQuickMenu(
              key: ValueKey('task_hub_page_quick_${entry.todo.id}_more'),
              items: overflowActions,
              onSelected: onQuickAction,
            ),
          if (showPriorityControls && entry.todo.status != 'done')
            _TaskHubAdjustMenu(
              todoId: entry.todo.id,
              onSelected: onQuickAction,
            ),
        ],
      ),
    ],
  );
}

class TaskHubFeedbackMenu extends StatelessWidget {
  const TaskHubFeedbackMenu({
    required this.todoId,
    required this.onSelected,
    super.key,
  });

  final String todoId;
  final ValueChanged<TaskPriorityFeedbackKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TaskPriorityFeedbackKind>(
      key: ValueKey('task_hub_feedback_$todoId'),
      tooltip: context.t.actions.taskHub.feedbackTitle,
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem<TaskPriorityFeedbackKind>(
          value: TaskPriorityFeedbackKind.notImportant,
          child: Text(context.t.actions.taskHub.feedbackNotImportant),
        ),
        PopupMenuItem<TaskPriorityFeedbackKind>(
          value: TaskPriorityFeedbackKind.recommendLater,
          child: Text(context.t.actions.taskHub.feedbackLater),
        ),
        PopupMenuItem<TaskPriorityFeedbackKind>(
          value: TaskPriorityFeedbackKind.decideMyself,
          child: Text(context.t.actions.taskHub.feedbackDecideMyself),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.more_horiz_rounded, size: 18),
      ),
    );
  }
}

class _TaskHubQuickButton extends StatelessWidget {
  const _TaskHubQuickButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = TaskHubQuickActionTone.secondary,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final TaskHubQuickActionTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final style = ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(Size(0, 34)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
    );
    if (tone == TaskHubQuickActionTone.primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style.copyWith(
        side: MaterialStatePropertyAll(
          BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _TaskHubAdjustMenu extends StatelessWidget {
  const _TaskHubAdjustMenu({
    required this.todoId,
    required this.onSelected,
  });

  final String todoId;
  final ValueChanged<TaskHubQuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return PopupMenuButton<TaskHubQuickAction>(
      key: ValueKey('task_hub_page_adjust_$todoId'),
      tooltip: context.t.actions.taskHub.actions.adjust,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => <PopupMenuEntry<TaskHubQuickAction>>[
        PopupMenuItem<TaskHubQuickAction>(
          key: ValueKey('task_hub_page_adjust_${todoId}_move_up'),
          value: TaskHubQuickAction.moveUpABit,
          child: Row(
            children: [
              const Icon(Icons.arrow_upward_rounded, size: 16),
              const SizedBox(width: 8),
              Text(context.t.actions.taskHub.actions.moveUpABit),
            ],
          ),
        ),
        PopupMenuItem<TaskHubQuickAction>(
          key: ValueKey('task_hub_page_adjust_${todoId}_move_down'),
          value: TaskHubQuickAction.moveDownABit,
          child: Row(
            children: [
              const Icon(Icons.arrow_downward_rounded, size: 16),
              const SizedBox(width: 8),
              Text(context.t.actions.taskHub.actions.moveDownABit),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<TaskHubQuickAction>(
          key: ValueKey('task_hub_page_adjust_${todoId}_restore_ai'),
          value: TaskHubQuickAction.restoreAiOrder,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16),
              const SizedBox(width: 8),
              Text(context.t.actions.taskHub.actions.restoreAiOrder),
            ],
          ),
        ),
      ],
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          style: ButtonStyle(
            minimumSize: const MaterialStatePropertyAll(Size(0, 34)),
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            ),
            side: MaterialStatePropertyAll(
              BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
            ),
          ),
          icon: const Icon(Icons.swap_vert_rounded, size: 16),
          label: Text(context.t.actions.taskHub.actions.adjust),
        ),
      ),
    );
  }
}

class _TaskHubQuickMenu extends StatelessWidget {
  const _TaskHubQuickMenu({
    required this.items,
    required this.onSelected,
    super.key,
  });

  final List<TaskHubQuickActionItem> items;
  final ValueChanged<TaskHubQuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final orderedItems = [...items];
    final safeItems = orderedItems
        .where((item) => !_isDestructiveTaskHubQuickAction(item.action))
        .toList(growable: false);
    final destructiveItems = orderedItems
        .where((item) => _isDestructiveTaskHubQuickAction(item.action))
        .toList(growable: false);
    return PopupMenuButton<TaskHubQuickAction>(
      tooltip: context.t.actions.taskHub.actions.more,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => <PopupMenuEntry<TaskHubQuickAction>>[
        for (final item in safeItems) _taskHubQuickMenuItem(context, item),
        if (safeItems.isNotEmpty && destructiveItems.isNotEmpty)
          const PopupMenuDivider(),
        for (final item in destructiveItems)
          _taskHubQuickMenuItem(context, item),
      ],
      child: IgnorePointer(
        child: OutlinedButton(
          onPressed: () {},
          style: ButtonStyle(
            minimumSize: const MaterialStatePropertyAll(Size(40, 34)),
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            ),
            side: MaterialStatePropertyAll(
              BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
            ),
          ),
          child: const Icon(Icons.more_horiz_rounded, size: 18),
        ),
      ),
    );
  }
}

PopupMenuItem<TaskHubQuickAction> _taskHubQuickMenuItem(
  BuildContext context,
  TaskHubQuickActionItem item,
) {
  final emphasis = _taskHubOverflowEmphasisFor(item.action);
  final colorScheme = Theme.of(context).colorScheme;
  final foregroundColor = switch (emphasis) {
    _TaskHubOverflowEmphasis.destructive => colorScheme.error,
    _TaskHubOverflowEmphasis.secondary => colorScheme.onSurfaceVariant,
    _TaskHubOverflowEmphasis.neutral => colorScheme.onSurfaceVariant,
    _TaskHubOverflowEmphasis.defaultTone => null,
  };
  final fontWeight = switch (emphasis) {
    _TaskHubOverflowEmphasis.destructive => FontWeight.w600,
    _TaskHubOverflowEmphasis.secondary => FontWeight.w500,
    _TaskHubOverflowEmphasis.neutral => FontWeight.w400,
    _TaskHubOverflowEmphasis.defaultTone => null,
  };
  return PopupMenuItem<TaskHubQuickAction>(
    value: item.action,
    child: Row(
      children: [
        Icon(item.icon, size: 16, color: foregroundColor),
        const SizedBox(width: 8),
        Text(
          item.label,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: fontWeight,
          ),
        ),
      ],
    ),
  );
}

enum _TaskHubOverflowEmphasis {
  defaultTone,
  neutral,
  secondary,
  destructive,
}

_TaskHubOverflowEmphasis _taskHubOverflowEmphasisFor(
  TaskHubQuickAction action,
) {
  return switch (action) {
    TaskHubQuickAction.today => _TaskHubOverflowEmphasis.neutral,
    TaskHubQuickAction.redo => _TaskHubOverflowEmphasis.secondary,
    TaskHubQuickAction.dismiss => _TaskHubOverflowEmphasis.destructive,
    _ => _TaskHubOverflowEmphasis.defaultTone,
  };
}

bool _isDestructiveTaskHubQuickAction(TaskHubQuickAction action) {
  return action == TaskHubQuickAction.dismiss;
}
