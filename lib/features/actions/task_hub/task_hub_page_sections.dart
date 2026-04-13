import 'package:flutter/material.dart';

import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_card_anchor.dart';
import 'task_hub_entry_card.dart';
import 'task_hub_priority_animation_controller.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

enum TaskHubPageSectionKind {
  focus,
  open,
  scheduled,
  decide,
  done,
}

class TaskHubPageSection extends StatelessWidget {
  const TaskHubPageSection({
    required this.title,
    required this.sectionKey,
    required this.headerCount,
    required this.entries,
    required this.checklistProgressByTodoId,
    required this.sectionKind,
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.restoredTodoId,
    this.footer,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.toggleKey,
    this.anchorRegistry,
    this.anchorId,
    this.inlineAnimation,
    this.priorityPendingTodoId,
    this.priorityLocalFallbackTodoId,
    this.onInlineAnimationCompleted,
    this.nowLocal,
    super.key,
  });

  final String title;
  final Key sectionKey;
  final int headerCount;
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
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final Key? toggleKey;
  final TaskHubCardAnchorRegistry? anchorRegistry;
  final String? anchorId;
  final TaskHubPriorityInlineAnimationState? inlineAnimation;
  final String? priorityPendingTodoId;
  final String? priorityLocalFallbackTodoId;
  final VoidCallback? onInlineAnimationCompleted;
  final DateTime? nowLocal;

  @override
  Widget build(BuildContext context) {
    if (headerCount == 0 && entries.isEmpty && footer == null) {
      return const SizedBox.shrink();
    }
    Widget section = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        key: sectionKey,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskHubSectionHeader(
              title: title,
              count: headerCount,
              kind: sectionKind,
              collapsed: collapsed,
              onToggleCollapsed: onToggleCollapsed,
              toggleKey: toggleKey,
            ),
            if (!collapsed && entries.isNotEmpty) ...[
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
                  anchorRegistry: anchorRegistry,
                  inlineAnimation: inlineAnimation,
                  showPriorityPendingBadge:
                      entries[i].todo.id == priorityPendingTodoId,
                  showPriorityLocalFallbackBadge:
                      entries[i].todo.id == priorityLocalFallbackTodoId,
                  onInlineAnimationCompleted: onInlineAnimationCompleted,
                  nowLocal: nowLocal,
                ),
                if (i != entries.length - 1) const SizedBox(height: 10),
              ],
            ],
            if (!collapsed && footer != null) ...[
              if (entries.isNotEmpty) const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
    if (anchorRegistry != null && anchorId != null) {
      section = TaskHubCardAnchor(
        todoId: anchorId!,
        registry: anchorRegistry!,
        child: section,
      );
    }
    return section;
  }
}

class TaskHubSectionHeader extends StatelessWidget {
  const TaskHubSectionHeader({
    required this.title,
    required this.count,
    required this.kind,
    this.hint,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.toggleKey,
    super.key,
  });

  final String title;
  final int count;
  final TaskHubPageSectionKind kind;
  final String? hint;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final Key? toggleKey;

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
            if (onToggleCollapsed != null) ...[
              const SizedBox(width: 4),
              IconButton(
                key: toggleKey,
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  color: tone.foreground,
                ),
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
              ),
            ],
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
    TaskHubPageSectionKind.open => _TaskHubSectionTone(
        foreground: scheme.secondary,
        background: scheme.secondaryContainer.withOpacity(0.68),
        border: scheme.secondary.withOpacity(0.18),
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
