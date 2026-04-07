import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_action_widgets.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

enum TaskHubPageSectionKind {
  focus,
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
    final sectionCount = entries.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        key: sectionKey,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskHubSectionHeader(
              title: title,
              count: sectionCount,
              kind: sectionKind,
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

class TaskHubSectionHeader extends StatelessWidget {
  const TaskHubSectionHeader({
    required this.title,
    required this.count,
    required this.kind,
    this.hint,
    super.key,
  });

  final String title;
  final int count;
  final TaskHubPageSectionKind kind;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final tone = _taskHubSectionTone(theme, kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: tone.foreground,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tone.foreground,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tone.background,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: tone.border ?? tokens.borderSubtle.withOpacity(0.8),
                ),
              ),
              child: Text(
                count.toString(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

final class _TaskHubSectionTone {
  const _TaskHubSectionTone({
    required this.foreground,
    required this.background,
    this.border,
  });

  final Color foreground;
  final Color background;
  final Color? border;
}

_TaskHubSectionTone _taskHubSectionTone(
  ThemeData theme,
  TaskHubPageSectionKind kind,
) {
  final scheme = theme.colorScheme;
  return switch (kind) {
    TaskHubPageSectionKind.focus => _TaskHubSectionTone(
        foreground: scheme.primary,
        background: scheme.primaryContainer.withOpacity(0.7),
        border: scheme.primary.withOpacity(0.18),
      ),
    TaskHubPageSectionKind.scheduled => _TaskHubSectionTone(
        foreground: scheme.secondary,
        background: scheme.secondaryContainer.withOpacity(0.68),
        border: scheme.secondary.withOpacity(0.18),
      ),
    TaskHubPageSectionKind.decide => _TaskHubSectionTone(
        foreground: scheme.tertiary,
        background: scheme.tertiaryContainer.withOpacity(0.68),
        border: scheme.tertiary.withOpacity(0.18),
      ),
    TaskHubPageSectionKind.done => _TaskHubSectionTone(
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest.withOpacity(0.56),
        border: scheme.outlineVariant.withOpacity(0.4),
      ),
  };
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
    final metaChips = <Widget>[
      _TaskHubMetaChip(label: _subtitle(context, entry), emphasize: true),
      if (checklistProgressText != null)
        _TaskHubMetaChip(
          child: Text(
            checklistProgressText,
            key: ValueKey('task_hub_checklist_progress_${entry.todo.id}'),
          ),
        ),
    ];
    final supportingText =
        (entry.reasonText ?? '').isNotEmpty ? entry.reasonText! : null;
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
      padding: const EdgeInsets.all(6),
      child: Container(
        key: ValueKey('task_hub_page_item_${entry.todo.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpenTodo,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: metaChips,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.todo.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (supportingText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              supportingText,
                              key: ValueKey(
                                  'task_priority_reason_${entry.todo.id}'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (supportingText == null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _subtitle(context, entry),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final action in layout.$1)
                      TaskHubQuickButton(
                        key: ValueKey(
                          'task_hub_page_quick_${entry.todo.id}_${action.action.name}',
                        ),
                        label: action.label,
                        icon: action.icon,
                        tone: action.tone,
                        onPressed: () => onQuickAction(action.action),
                      ),
                    if (layout.$2.isNotEmpty)
                      TaskHubQuickMenu(
                        key: ValueKey(
                            'task_hub_page_quick_${entry.todo.id}_more'),
                        items: layout.$2,
                        onSelected: onQuickAction,
                      ),
                  ],
                ),
                if (showPriorityControls && entry.todo.status != 'done') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                        neutralLabel:
                            context.t.actions.taskHub.actions.increaseUrgency,
                        raisedLabel:
                            context.t.actions.taskHub.nudges.urgencyRaised,
                        loweredLabel:
                            context.t.actions.taskHub.nudges.urgencyLowered,
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
                        neutralLabel: context
                            .t.actions.taskHub.actions.increaseImportance,
                        raisedLabel:
                            context.t.actions.taskHub.nudges.importanceRaised,
                        loweredLabel:
                            context.t.actions.taskHub.nudges.importanceLowered,
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
                    const SizedBox(height: 6),
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

class _TaskHubMetaChip extends StatelessWidget {
  const _TaskHubMetaChip({
    this.label,
    this.child,
    this.emphasize = false,
  }) : assert(label != null || child != null);

  final String? label;
  final Widget? child;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final foregroundColor = emphasize
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final backgroundColor = emphasize
        ? theme.colorScheme.primaryContainer.withOpacity(0.72)
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.48);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderSubtle.withOpacity(0.78)),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.labelSmall!.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
        child: child ?? Text(label!),
      ),
    );
  }
}

class _TaskHubPriorityControl extends StatelessWidget {
  const _TaskHubPriorityControl({
    required this.stateKey,
    required this.decreaseButtonKey,
    required this.increaseButtonKey,
    required this.icon,
    required this.direction,
    required this.neutralLabel,
    required this.raisedLabel,
    required this.loweredLabel,
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
  final String neutralLabel;
  final String raisedLabel;
  final String loweredLabel;
  final String semanticsLabel;
  final String decreaseTooltip;
  final String increaseTooltip;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  bool get _isUp => direction == TaskPriorityNudgeDirection.up;
  bool get _isDown => direction == TaskPriorityNudgeDirection.down;
  String get _label {
    if (_isDown) return decreaseTooltip;
    return neutralLabel;
  }

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 14, color: foregroundColor),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _isUp || _isDown
                      ? highlightColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
