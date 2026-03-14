import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
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
    required this.sectionKind,
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.footer,
    super.key,
  });

  final String title;
  final Key sectionKey;
  final List<TaskPriorityEntry> entries;
  final TaskHubPageSectionKind sectionKind;
  final Future<void> Function(TaskPriorityEntry entry) onOpenTodo;
  final Future<void> Function(
      TaskPriorityEntry entry, TaskHubQuickAction action) onQuickAction;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  )? onFeedback;
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
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.emphasize = false,
    super.key,
  });

  final TaskPriorityEntry entry;
  final VoidCallback onOpenTodo;
  final ValueChanged<TaskHubQuickAction> onQuickAction;
  final ValueChanged<TaskPriorityFeedbackKind>? onFeedback;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final layout = buildTaskHubQuickActionLayout(context, entry: entry);
    return Container(
      key: ValueKey('task_hub_page_item_${entry.todo.id}'),
      decoration: BoxDecoration(
        color: emphasize ? tokens.surface2 : null,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      padding: const EdgeInsets.all(8),
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
                  if (onFeedback != null && (entry.reasonText ?? '').isNotEmpty)
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in layout.$1)
                _TaskHubQuickButton(
                  key: ValueKey(
                      'task_hub_page_quick_${entry.todo.id}_${action.action.name}'),
                  label: action.label,
                  icon: action.icon,
                  tone: action.tone,
                  onPressed: () => onQuickAction(action.action),
                ),
              if (layout.$2.isNotEmpty)
                _TaskHubQuickMenu(
                  key: ValueKey('task_hub_page_quick_${entry.todo.id}_more'),
                  items: layout.$2,
                  onSelected: onQuickAction,
                ),
            ],
          ),
        ],
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
    return PopupMenuButton<TaskHubQuickAction>(
      tooltip: context.t.actions.taskHub.actions.more,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem<TaskHubQuickAction>(
            value: item.action,
            child: Row(
              children: [
                Icon(item.icon, size: 16),
                const SizedBox(width: 8),
                Text(item.label),
              ],
            ),
          ),
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
