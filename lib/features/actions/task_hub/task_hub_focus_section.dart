import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_card_anchor.dart';
import 'task_hub_entry_card.dart';
import 'task_hub_page_sections.dart';
import 'task_hub_priority_animation_controller.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

class TaskHubFocusSection extends StatelessWidget {
  const TaskHubFocusSection({
    required this.entries,
    required this.checklistProgressByTodoId,
    required this.onOpenTodo,
    required this.onQuickAction,
    this.onFeedback,
    this.restoredTodoId,
    this.anchorRegistry,
    this.anchorId,
    this.inlineAnimation,
    this.priorityPendingTodoId,
    this.priorityLocalFallbackTodoId,
    this.onInlineAnimationCompleted,
    this.nowLocal,
    super.key,
  });

  final List<TaskPriorityEntry> entries;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  final Future<void> Function(
      TaskPriorityEntry entry, TaskHubQuickAction action) onQuickAction;
  final Future<void> Function(TaskPriorityEntry entry) onOpenTodo;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  )? onFeedback;
  final String? restoredTodoId;
  final TaskHubCardAnchorRegistry? anchorRegistry;
  final String? anchorId;
  final TaskHubPriorityInlineAnimationState? inlineAnimation;
  final String? priorityPendingTodoId;
  final String? priorityLocalFallbackTodoId;
  final VoidCallback? onInlineAnimationCompleted;
  final DateTime? nowLocal;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final tokens = SlTokens.of(context);
    Widget section = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        key: const ValueKey('task_hub_page_section_focus'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskHubSectionHeader(
              title: context.t.actions.taskHub.focusSection,
              count: entries.length,
              kind: TaskHubPageSectionKind.focus,
              hint: context.t.actions.taskHub.focusHint,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i++) ...[
              TaskHubEntryCard(
                entry: entries[i],
                checklistProgressByTodoId: checklistProgressByTodoId,
                emphasize: i == 0,
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
              if (i != entries.length - 1)
                Divider(
                    color: tokens.borderSubtle.withOpacity(0.9), height: 20),
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
