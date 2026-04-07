import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_actions.dart';

ButtonStyle taskHubQuickActionButtonStyle() {
  return ButtonStyle(
    minimumSize: const MaterialStatePropertyAll(Size(0, 34)),
    padding: const MaterialStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: MaterialStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    ),
  );
}

class TaskHubQuickButton extends StatelessWidget {
  const TaskHubQuickButton({
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
    final style = taskHubQuickActionButtonStyle();
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

class TaskHubQuickMenu extends StatelessWidget {
  const TaskHubQuickMenu({
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
          style: taskHubQuickActionButtonStyle().copyWith(
            minimumSize: const MaterialStatePropertyAll(Size(40, 34)),
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
