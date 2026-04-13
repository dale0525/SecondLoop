import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_card_anchor.dart';
import 'task_hub_priority_animation_controller.dart';
import 'task_hub_priority_controls.dart';
import 'task_hub_quick_actions.dart';
import 'task_hub_relative_time.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

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
    this.showPriorityPendingBadge = false,
    this.showPriorityLocalFallbackBadge = false,
    this.anchorRegistry,
    this.inlineAnimation,
    this.onInlineAnimationCompleted,
    this.nowLocal,
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
  final bool showPriorityPendingBadge;
  final bool showPriorityLocalFallbackBadge;
  final TaskHubCardAnchorRegistry? anchorRegistry;
  final TaskHubPriorityInlineAnimationState? inlineAnimation;
  final VoidCallback? onInlineAnimationCompleted;
  final DateTime? nowLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final checklistProgress = checklistProgressByTodoId[entry.todo.id];
    final checklistProgressText =
        checklistProgress == null || checklistProgress.totalCount <= 0
            ? null
            : '${checklistProgress.doneCount}/${checklistProgress.totalCount}';
    final restoredBackground =
        theme.colorScheme.primaryContainer.withOpacity(emphasize ? 0.64 : 0.58);
    final restoredBorder = theme.colorScheme.primary.withOpacity(0.28);
    final defaultBackground = emphasize ? tokens.surface2 : null;
    final relativeTimeText = entry.todo.status == 'done'
        ? null
        : formatTaskHubRelativeTime(
            dueAtMs: entry.todo.dueAtMs,
            nowLocal: nowLocal ?? DateTime.now(),
            labels: TaskHubRelativeTimeLabels(
              noDeadline: context.t.actions.taskHub.relativeTime.noDeadline,
              today: context.t.actions.taskHub.relativeTime.today,
              inHours: (count) =>
                  context.t.actions.taskHub.relativeTime.inHours(count: count),
              inDays: (count) =>
                  context.t.actions.taskHub.relativeTime.inDays(count: count),
              inWeeks: (count) =>
                  context.t.actions.taskHub.relativeTime.inWeeks(count: count),
              overdueHours: (count) => context.t.actions.taskHub.relativeTime
                  .overdueHours(count: count),
              overdueDays: (count) => context.t.actions.taskHub.relativeTime
                  .overdueDays(count: count),
              overdueWeeks: (count) => context.t.actions.taskHub.relativeTime
                  .overdueWeeks(count: count),
            ),
          );
    final metaChips = <Widget>[
      _TaskHubMetaChip(label: _subtitle(context, entry), emphasize: true),
      if (_rankingReasonLabel(context, entry) case final rankingReasonLabel?)
        _TaskHubMetaChip(
          child: Text(
            rankingReasonLabel,
            key: ValueKey('task_hub_reason_chip_${entry.todo.id}'),
          ),
        ),
      if (checklistProgressText != null)
        _TaskHubMetaChip(
          child: Text(
            checklistProgressText,
            key: ValueKey('task_hub_checklist_progress_${entry.todo.id}'),
          ),
        ),
      if (showPriorityPendingBadge)
        _TaskHubMetaChip(
          child: Text(
            context.t.actions.taskHub.priorityPending,
            key: ValueKey('task_hub_priority_pending_badge_${entry.todo.id}'),
          ),
        ),
      if (showPriorityLocalFallbackBadge)
        _TaskHubMetaChip(
          child: Text(
            context.t.actions.taskHub.priorityLocalFallback,
            key: ValueKey(
              'task_hub_priority_local_fallback_badge_${entry.todo.id}',
            ),
          ),
        ),
    ];
    final supportingText = emphasize && (entry.reasonText ?? '').isNotEmpty
        ? entry.reasonText!
        : null;
    Widget card = AnimatedContainer(
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.todo.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (relativeTimeText != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  relativeTimeText,
                                  key: ValueKey(
                                    'task_hub_relative_time_${entry.todo.id}',
                                  ),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: metaChips,
                          ),
                          if (supportingText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              supportingText,
                              key: ValueKey(
                                'task_priority_reason_${entry.todo.id}',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onFeedback != null && supportingText != null)
                      TaskHubFeedbackMenu(
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
            buildTaskHubPriorityControls(
              context,
              entry: entry,
              onQuickAction: onQuickAction,
              showPriorityControls: showPriorityControls,
              compactActions: !emphasize,
            ),
          ],
        ),
      ),
    );
    if (anchorRegistry != null) {
      card = TaskHubCardAnchor(
        todoId: entry.todo.id,
        registry: anchorRegistry!,
        child: card,
      );
    }
    final animation = inlineAnimation;
    if (animation == null || animation.todoId != entry.todo.id) {
      return card;
    }
    return TweenAnimationBuilder<Offset>(
      key: ValueKey(
        'task_hub_priority_inline_animation_${entry.todo.id}_${animation.token}',
      ),
      tween: Tween<Offset>(
        begin: animation.beginOffset,
        end: Offset.zero,
      ),
      duration: animation.duration,
      curve: Curves.easeOutCubic,
      onEnd: onInlineAnimationCompleted,
      child: card,
      builder: (context, offset, child) {
        return Transform.translate(
          key: ValueKey('task_hub_priority_inline_animation_${entry.todo.id}'),
          offset: offset,
          child: child,
        );
      },
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

  String? _rankingReasonLabel(BuildContext context, TaskPriorityEntry entry) {
    return switch (entry.userMoveDirection) {
      TaskPriorityUserMoveDirection.up =>
        context.t.actions.taskHub.reasons.manuallyMovedUp,
      TaskPriorityUserMoveDirection.down =>
        context.t.actions.taskHub.reasons.manuallyMovedDown,
      TaskPriorityUserMoveDirection.none => _defaultRankingReasonLabel(
          context,
          entry,
        ),
    };
  }

  String? _defaultRankingReasonLabel(
    BuildContext context,
    TaskPriorityEntry entry,
  ) {
    if (entry.reasons.contains(TaskPriorityReasonKind.aiSuggested) ||
        (entry.reasonText ?? '').isNotEmpty) {
      return context.t.actions.taskHub.reasons.aiPromoted;
    }
    if (entry.isReviewDue) {
      return context.t.actions.taskHub.reasons.reviewDue;
    }
    if (entry.isInProgress) {
      return context.t.actions.taskHub.reasons.inProgress;
    }
    return null;
  }
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
