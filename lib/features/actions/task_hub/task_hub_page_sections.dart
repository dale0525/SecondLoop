import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_actions.dart';

enum TaskHubPageSectionKind {
  scheduled,
  dueReview,
  unscheduled,
  done,
}

class TaskHubPageSection extends StatelessWidget {
  const TaskHubPageSection({
    required this.title,
    required this.todos,
    required this.sectionKind,
    required this.onQuickAction,
    required this.onOpenTodo,
    this.totalCount,
    this.footer,
    super.key,
  });

  final String title;
  final List<Todo> todos;
  final TaskHubPageSectionKind sectionKind;
  final int? totalCount;
  final Widget? footer;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)
      onQuickAction;
  final Future<void> Function(Todo todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty && footer == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: tokens.borderSubtle.withOpacity(0.9),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      (totalCount ?? todos.length).toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (todos.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < todos.length; i++)
                Padding(
                  padding:
                      EdgeInsets.only(bottom: i == todos.length - 1 ? 0 : 8),
                  child: _TaskHubPageTodoRow(
                    todo: todos[i],
                    sectionKind: sectionKind,
                    onQuickAction: onQuickAction,
                    onOpenTodo: onOpenTodo,
                  ),
                ),
            ],
            if (footer != null) ...[
              if (todos.isNotEmpty) const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class TaskHubPageMergedUnscheduledSection extends StatelessWidget {
  const TaskHubPageMergedUnscheduledSection({
    required this.dueReviewTodos,
    required this.unscheduledTodos,
    required this.onQuickAction,
    required this.onOpenTodo,
    super.key,
  });

  final List<Todo> dueReviewTodos;
  final List<Todo> unscheduledTodos;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)
      onQuickAction;
  final Future<void> Function(Todo todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    if (dueReviewTodos.isEmpty && unscheduledTodos.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;
    final totalCount = dueReviewTodos.length + unscheduledTodos.length;

    Widget buildSubgroup({
      required String keySuffix,
      required String title,
      required List<Todo> todos,
      required TaskHubPageSectionKind sectionKind,
    }) {
      if (todos.isEmpty) return const SizedBox.shrink();
      return Column(
        key: ValueKey('task_hub_page_section_unscheduled_$keySuffix'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: tokens.borderSubtle.withOpacity(0.9),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    todos.length.toString(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < todos.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == todos.length - 1 ? 0 : 8),
              child: _TaskHubPageTodoRow(
                todo: todos[i],
                sectionKind: sectionKind,
                onQuickAction: onQuickAction,
                onOpenTodo: onOpenTodo,
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.t.actions.taskHub.unscheduledSection,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: tokens.borderSubtle.withOpacity(0.9),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      totalCount.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            buildSubgroup(
              keySuffix: 'review',
              title: context.t.actions.taskHub.reviewSection,
              todos: dueReviewTodos,
              sectionKind: TaskHubPageSectionKind.dueReview,
            ),
            if (dueReviewTodos.isNotEmpty && unscheduledTodos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSubtle.withOpacity(0.9),
              ),
              const SizedBox(height: 10),
            ],
            buildSubgroup(
              keySuffix: 'plain',
              title: context.t.actions.taskHub.unscheduledSection,
              todos: unscheduledTodos,
              sectionKind: TaskHubPageSectionKind.unscheduled,
            ),
          ],
        ),
      ),
    );
  }
}

class TaskHubPageDoneLoadMoreButton extends StatelessWidget {
  const TaskHubPageDoneLoadMoreButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        key: const ValueKey('task_hub_page_done_load_more'),
        tooltip: context.t.actions.agenda.viewAll,
        onPressed: onPressed,
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    );
  }
}

class _TaskHubPageTodoRow extends StatelessWidget {
  const _TaskHubPageTodoRow({
    required this.todo,
    required this.sectionKind,
    required this.onQuickAction,
    required this.onOpenTodo,
  });

  final Todo todo;
  final TaskHubPageSectionKind sectionKind;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)
      onQuickAction;
  final Future<void> Function(Todo todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final dueAtMs = todo.dueAtMs;
    final dueAtLocal = dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final dueAtText = dueAtLocal == null
        ? null
        : '${MaterialLocalizations.of(context).formatShortDate(dueAtLocal)} '
            '${MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(dueAtLocal),
            alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
          )}';
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final overdue = dueAtLocal != null &&
        dueAtLocal.isBefore(DateTime.now()) &&
        todo.status != 'done' &&
        todo.status != 'dismissed';
    final dotColor = todo.status == 'done'
        ? const Color(0xFF22C55E)
        : overdue
            ? colorScheme.error
            : colorScheme.primary;
    final actionLayout = buildTaskHubQuickActionLayout(
      context,
      todo: todo,
      sectionKind: _resolveQuickActionSectionKind(),
      dueAtLocal: dueAtLocal,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface2.withOpacity(0.55),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('task_hub_page_item_${todo.id}'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: () => unawaited(onOpenTodo(todo)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: dotColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (dueAtText != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      dueAtText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (actionLayout.$1.isNotEmpty || actionLayout.$2.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final actionChip in actionLayout.$1)
                    _TaskHubPageQuickButton(
                      key: ValueKey(
                        'task_hub_page_quick_${todo.id}_${actionChip.action.name}',
                      ),
                      icon: actionChip.icon,
                      label: actionChip.label,
                      tone: actionChip.tone,
                      onPressed: () => onQuickAction(todo, actionChip.action),
                    ),
                  if (actionLayout.$2.isNotEmpty)
                    _TaskHubPageQuickMenu(
                      key: ValueKey('task_hub_page_quick_${todo.id}_more'),
                      items: actionLayout.$2,
                      onSelected: (action) =>
                          unawaited(onQuickAction(todo, action)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  TaskHubQuickActionSectionKind _resolveQuickActionSectionKind() {
    return switch (sectionKind) {
      TaskHubPageSectionKind.scheduled =>
        TaskHubQuickActionSectionKind.scheduled,
      TaskHubPageSectionKind.dueReview =>
        TaskHubQuickActionSectionKind.dueReview,
      TaskHubPageSectionKind.unscheduled =>
        TaskHubQuickActionSectionKind.unscheduled,
      TaskHubPageSectionKind.done => TaskHubQuickActionSectionKind.done,
    };
  }
}

class _TaskHubPageQuickButton extends StatelessWidget {
  const _TaskHubPageQuickButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    this.tone = TaskHubQuickActionTone.secondary,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final TaskHubQuickActionTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final borderRadius = BorderRadius.circular(99);
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(Size(0, 30)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      textStyle: MaterialStatePropertyAll(
        Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );

    final button = tone == TaskHubQuickActionTone.primary
        ? FilledButton.icon(
            onPressed: onPressed,
            style: baseStyle,
            icon: Icon(icon, size: 14),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: baseStyle.copyWith(
              side: MaterialStatePropertyAll(
                BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
              ),
            ),
            icon: Icon(icon, size: 14),
            label: Text(label),
          );

    return Tooltip(
      message: label,
      child: IconTheme.merge(
        data: IconThemeData(
          color: tone == TaskHubQuickActionTone.primary
              ? colorScheme.onPrimary
              : null,
        ),
        child: button,
      ),
    );
  }
}

class _TaskHubPageQuickMenu extends StatelessWidget {
  const _TaskHubPageQuickMenu({
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: tokens.borderSubtle.withOpacity(0.9),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Icon(Icons.more_horiz_rounded, size: 16),
        ),
      ),
    );
  }
}
