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
    this.anchorRegistry,
    this.inlineAnimation,
    this.onInlineAnimationCompleted,
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
  final TaskHubCardAnchorRegistry? anchorRegistry;
  final TaskHubPriorityInlineAnimationState? inlineAnimation;
  final VoidCallback? onInlineAnimationCompleted;

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
                  anchorRegistry: anchorRegistry,
                  inlineAnimation: inlineAnimation,
                  onInlineAnimationCompleted: onInlineAnimationCompleted,
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
