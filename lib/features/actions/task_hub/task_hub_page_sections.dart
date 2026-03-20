import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

enum TaskHubPageSectionKind {
  scheduled,
  decide,
  done,
}

class TaskHubPageSection extends StatelessWidget {
  const TaskHubPageSection({
    required this.title,
    required this.sectionKey,
    required this.entries,
    required this.checklistProgressByTodoId,
    required this.sectionKind,
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.restoredTodoId,
    this.footer,
    super.key,
  });

  final String title;
  final Key sectionKey;
  final List<TaskPriorityEntry> entries;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  final TaskHubPageSectionKind sectionKind;
  final Future<void> Function(TaskPriorityEntry entry) onOpenTodo;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskHubQuickAction action,
  ) onQuickAction;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  )? onFeedback;
  final String? restoredTodoId;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && footer == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        key: sectionKey,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < entries.length; i++) ...[
                TaskHubEntryCard(
                  entry: entries[i],
                  checklistProgressByTodoId: checklistProgressByTodoId,
                  recentlyRestored: entries[i].todo.id == restoredTodoId,
                  onOpenTodo: () => onOpenTodo(entries[i]),
                  onQuickAction: (action) => onQuickAction(entries[i], action),
                  onFeedback: onFeedback == null
                      ? null
                      : (feedback) => onFeedback!(entries[i], feedback),
                ),
                if (i != entries.length - 1) const SizedBox(height: 10),
              ],
            ],
            if (footer != null) ...[
              if (entries.isNotEmpty) const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class TaskHubEntryCard extends StatelessWidget {
  const TaskHubEntryCard({
    required this.entry,
    required this.checklistProgressByTodoId,
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.emphasize = false,
    this.recentlyRestored = false,
    this.showPriorityControls = true,
    super.key,
  });

  final TaskPriorityEntry entry;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  final VoidCallback onOpenTodo;
  final ValueChanged<TaskHubQuickAction> onQuickAction;
  final ValueChanged<TaskPriorityFeedbackKind>? onFeedback;
  final bool emphasize;
  final bool recentlyRestored;
  final bool showPriorityControls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final layout = buildTaskHubQuickActionLayout(context, entry: entry);
    final checklistProgress = checklistProgressByTodoId[entry.todo.id];
    final checklistProgressText =
        checklistProgress == null || checklistProgress.totalCount <= 0
            ? null
            : '${checklistProgress.doneCount}/${checklistProgress.totalCount}';
    final restoredBackground =
        theme.colorScheme.primaryContainer.withOpacity(emphasize ? 0.64 : 0.58);
    final restoredBorder = theme.colorScheme.primary.withOpacity(0.28);
    final defaultBackground = emphasize ? tokens.surface2 : null;
    return AnimatedContainer(
      key: ValueKey(
        'task_hub_page_item_state_${entry.todo.id}_${recentlyRestored ? 'restored' : 'default'}',
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: recentlyRestored ? restoredBackground : defaultBackground,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: recentlyRestored ? Border.all(color: restoredBorder) : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        key: ValueKey('task_hub_page_item_${entry.todo.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpenTodo,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.todo.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle(context, entry),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (checklistProgressText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              checklistProgressText,
                              key: ValueKey(
                                'task_hub_checklist_progress_${entry.todo.id}',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if ((entry.reasonText ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry.reasonText!,
                              key: ValueKey(
                                  'task_priority_reason_${entry.todo.id}'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onFeedback != null &&
                        (entry.reasonText ?? '').isNotEmpty)
                      _TaskHubFeedbackMenu(
                        todoId: entry.todo.id,
                        onSelected: onFeedback!,
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in layout.$1)
                      _TaskHubQuickButton(
                        key: ValueKey(
                          'task_hub_page_quick_${entry.todo.id}_${action.action.name}',
                        ),
                        label: action.label,
                        icon: action.icon,
                        tone: action.tone,
                        onPressed: () => onQuickAction(action.action),
                      ),
                    if (layout.$2.isNotEmpty)
                      _TaskHubQuickMenu(
                        key: ValueKey(
                            'task_hub_page_quick_${entry.todo.id}_more'),
                        items: layout.$2,
                        onSelected: onQuickAction,
                      ),
                  ],
                ),
                if (showPriorityControls && entry.todo.status != 'done') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _TaskHubPriorityControl(
                        key: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_urgency',
                        ),
                        stateKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_urgency_${_priorityStateSuffix(entry.manualUrgencyNudgeDirection)}',
                        ),
                        decreaseButtonKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_urgency_decrease',
                        ),
                        increaseButtonKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_urgency_increase',
                        ),
                        icon: Icons.priority_high_rounded,
                        direction: entry.manualUrgencyNudgeDirection,
                        semanticsLabel:
                            context.t.actions.taskHub.actions.increaseUrgency,
                        decreaseTooltip:
                            context.t.actions.taskHub.actions.decreaseUrgency,
                        increaseTooltip:
                            context.t.actions.taskHub.actions.increaseUrgency,
                        onDecrease: () =>
                            onQuickAction(TaskHubQuickAction.decreaseUrgency),
                        onIncrease: () =>
                            onQuickAction(TaskHubQuickAction.increaseUrgency),
                      ),
                      const SizedBox(width: 8),
                      _TaskHubPriorityControl(
                        key: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_importance',
                        ),
                        stateKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_importance_${_priorityStateSuffix(entry.manualImportanceNudgeDirection)}',
                        ),
                        decreaseButtonKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_importance_decrease',
                        ),
                        increaseButtonKey: ValueKey(
                          'task_hub_page_priority_${entry.todo.id}_importance_increase',
                        ),
                        icon: Icons.keyboard_double_arrow_up_rounded,
                        direction: entry.manualImportanceNudgeDirection,
                        semanticsLabel: context
                            .t.actions.taskHub.actions.increaseImportance,
                        decreaseTooltip: context
                            .t.actions.taskHub.actions.decreaseImportance,
                        increaseTooltip: context
                            .t.actions.taskHub.actions.increaseImportance,
                        onDecrease: () => onQuickAction(
                            TaskHubQuickAction.decreaseImportance),
                        onIncrease: () => onQuickAction(
                            TaskHubQuickAction.increaseImportance),
                      ),
                    ],
                  ),
                  if (entry.hasManualNudges) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final item in _buildNudgePills(context, entry))
                          _TaskHubNudgePill(
                            key: ValueKey(
                              'task_hub_page_nudge_${entry.todo.id}_${item.keySuffix}',
                            ),
                            label: item.label,
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, TaskPriorityEntry entry) {
    if (entry.isOverdue) return context.t.actions.taskHub.overdueLabel;
    if (entry.isDueToday) return context.t.actions.taskHub.dueTodayLabel;
    if (entry.isInProgress) return context.t.actions.taskHub.inProgressLabel;
    if (entry.isReviewDue) return context.t.actions.taskHub.reviewDueLabel;
    if (entry.isFutureScheduled) {
      return context.t.actions.taskHub.scheduledLabel;
    }
    if (entry.isSnoozed) return context.t.actions.taskHub.snoozedLabel;
    return context.t.actions.taskHub.decideLabel;
  }

  String _priorityStateSuffix(TaskPriorityNudgeDirection direction) {
    return switch (direction) {
      TaskPriorityNudgeDirection.up => 'up',
      TaskPriorityNudgeDirection.down => 'down',
      TaskPriorityNudgeDirection.none => 'neutral',
    };
  }

  List<_NudgePillData> _buildNudgePills(
    BuildContext context,
    TaskPriorityEntry entry,
  ) {
    final pills = <_NudgePillData>[];
    switch (entry.manualUrgencyNudgeDirection) {
      case TaskPriorityNudgeDirection.up:
        pills.add(
          _NudgePillData(
            keySuffix: 'urgency_up',
            label: context.t.actions.taskHub.nudges.urgencyRaised,
          ),
        );
        break;
      case TaskPriorityNudgeDirection.down:
        pills.add(
          _NudgePillData(
            keySuffix: 'urgency_down',
            label: context.t.actions.taskHub.nudges.urgencyLowered,
          ),
        );
        break;
      case TaskPriorityNudgeDirection.none:
        break;
    }
    switch (entry.manualImportanceNudgeDirection) {
      case TaskPriorityNudgeDirection.up:
        pills.add(
          _NudgePillData(
            keySuffix: 'importance_up',
            label: context.t.actions.taskHub.nudges.importanceRaised,
          ),
        );
        break;
      case TaskPriorityNudgeDirection.down:
        pills.add(
          _NudgePillData(
            keySuffix: 'importance_down',
            label: context.t.actions.taskHub.nudges.importanceLowered,
          ),
        );
        break;
      case TaskPriorityNudgeDirection.none:
        break;
    }
    return pills;
  }
}

class _NudgePillData {
  const _NudgePillData({
    required this.keySuffix,
    required this.label,
  });

  final String keySuffix;
  final String label;
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
      minimumSize: const MaterialStatePropertyAll(Size(0, 40)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            minimumSize: const MaterialStatePropertyAll(Size(44, 40)),
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

class _TaskHubPriorityControl extends StatelessWidget {
  const _TaskHubPriorityControl({
    required this.stateKey,
    required this.decreaseButtonKey,
    required this.increaseButtonKey,
    required this.icon,
    required this.direction,
    required this.semanticsLabel,
    required this.decreaseTooltip,
    required this.increaseTooltip,
    required this.onDecrease,
    required this.onIncrease,
    super.key,
  });

  final Key stateKey;
  final Key decreaseButtonKey;
  final Key increaseButtonKey;
  final IconData icon;
  final TaskPriorityNudgeDirection direction;
  final String semanticsLabel;
  final String decreaseTooltip;
  final String increaseTooltip;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  bool get _isUp => direction == TaskPriorityNudgeDirection.up;
  bool get _isDown => direction == TaskPriorityNudgeDirection.down;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final highlightColor = _isUp
        ? theme.colorScheme.primary
        : _isDown
            ? theme.colorScheme.tertiary
            : theme.colorScheme.outlineVariant;
    final borderColor = (_isUp || _isDown)
        ? highlightColor.withOpacity(0.7)
        : tokens.borderSubtle.withOpacity(0.9);
    final backgroundColor = (_isUp || _isDown)
        ? (_isUp
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.tertiaryContainer)
            .withOpacity(0.45)
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.28);
    final badgeColor = (_isUp || _isDown)
        ? highlightColor
        : theme.colorScheme.surfaceContainerHighest;
    final foregroundColor = (_isUp || _isDown)
        ? (_isUp ? theme.colorScheme.onPrimary : theme.colorScheme.onTertiary)
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: semanticsLabel,
      enabled: true,
      child: AnimatedContainer(
        key: stateKey,
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: borderColor,
            width: (_isUp || _isDown) ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          boxShadow: (_isUp || _isDown)
              ? [
                  BoxShadow(
                    color: highlightColor.withOpacity(0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: foregroundColor),
            ),
            const SizedBox(height: 4),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: highlightColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TaskHubPriorityButton(
                  key: decreaseButtonKey,
                  icon: Icons.remove_rounded,
                  tooltip: decreaseTooltip,
                  emphasize: _isDown,
                  enabled: true,
                  onPressed: onDecrease,
                ),
                const SizedBox(width: 4),
                _TaskHubPriorityButton(
                  key: increaseButtonKey,
                  icon: Icons.add_rounded,
                  tooltip: increaseTooltip,
                  emphasize: _isUp,
                  enabled: true,
                  onPressed: onIncrease,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskHubNudgePill extends StatelessWidget {
  const _TaskHubNudgePill({
    required this.label,
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tokens.borderSubtle.withOpacity(0.85)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TaskHubPriorityButton extends StatelessWidget {
  const _TaskHubPriorityButton({
    required this.icon,
    required this.tooltip,
    required this.emphasize,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final bool emphasize;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final enabledOpacity = enabled ? 1.0 : 0.42;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(99),
        child: Opacity(
          opacity: enabledOpacity,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: emphasize
                  ? theme.colorScheme.primaryContainer.withOpacity(0.9)
                  : theme.colorScheme.surface,
              border: Border.all(
                color: emphasize
                    ? theme.colorScheme.primary.withOpacity(0.45)
                    : tokens.borderSubtle.withOpacity(0.9),
              ),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Icon(
              icon,
              size: 14,
              color: emphasize
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskHubFeedbackMenu extends StatelessWidget {
  const _TaskHubFeedbackMenu({
    required this.todoId,
    required this.onSelected,
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
