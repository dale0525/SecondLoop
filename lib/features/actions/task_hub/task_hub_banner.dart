import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_page_sections.dart';
import 'task_hub_quick_action_layout.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

class TaskHubBanner extends StatefulWidget {
  const TaskHubBanner({
    required this.snapshot,
    this.checklistProgressByTodoId = const <String, TodoChecklistProgress>{},
    this.showAiUpgradeHint = false,
    this.collapseSignal = 0,
    this.compact = false,
    this.onViewAll,
    this.onOpenTodo,
    this.onQuickAction,
    this.onFeedback,
    super.key,
  });

  final TaskPrioritySnapshot snapshot;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  final bool showAiUpgradeHint;
  final int collapseSignal;
  final bool compact;
  final VoidCallback? onViewAll;
  final Future<void> Function(TaskPriorityEntry entry)? onOpenTodo;
  final Future<void> Function(
      TaskPriorityEntry entry, TaskHubQuickAction action)? onQuickAction;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  )? onFeedback;

  @override
  State<TaskHubBanner> createState() => _TaskHubBannerState();
}

class _TaskHubBannerState extends State<TaskHubBanner> {
  var _expanded = false;

  @override
  void didUpdateWidget(covariant TaskHubBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseSignal != oldWidget.collapseSignal && _expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final primary = widget.snapshot.primaryFocus;
    final hasAiReason =
        widget.snapshot.source == TaskPrioritySnapshotSource.hybrid &&
            (primary?.reasonText ?? '').isNotEmpty;
    final outerPadding = widget.compact
        ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
        : const EdgeInsets.fromLTRB(12, 12, 12, 8);
    final innerPadding = widget.compact ? 10.0 : 12.0;
    final headerSpacing = widget.compact ? 4.0 : 6.0;
    final actionsSpacingTop = widget.compact ? 8.0 : 12.0;
    final primaryAction = primary == null
        ? null
        : primaryTaskHubQuickActionItemForEntry(
            context,
            entry: primary,
          );
    final secondaryAction = primary == null
        ? null
        : secondaryTaskHubQuickActionItemForEntry(
            context,
            entry: primary,
          );
    return Padding(
      padding: outerPadding,
      child: SlSurface(
        key: const ValueKey('task_hub_banner'),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.all(innerPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        primary == null
                            ? context.t.actions.taskHub.wrapUpTitle
                            : hasAiReason
                                ? context.t.actions.taskHub.aiRecommendedNow
                                : context.t.actions.taskHub.currentFocus,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ],
                ),
                SizedBox(height: headerSpacing),
                Text(
                  primary?.todo.title ??
                      context.t.actions.taskHub.wrapUpHeadline,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                SizedBox(height: headerSpacing),
                Text(
                  primary?.reasonText ?? _fallbackSubtitle(context),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (widget.showAiUpgradeHint && !hasAiReason) ...[
                  SizedBox(height: headerSpacing),
                  Text(
                    context.t.actions.taskHub.aiUpgradeHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
                SizedBox(height: actionsSpacingTop),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (primary != null &&
                        primaryAction != null &&
                        widget.onQuickAction != null)
                      SlButton(
                        key: const ValueKey('task_hub_banner_primary_action'),
                        onPressed: () => unawaited(
                          widget.onQuickAction!(
                            primary,
                            primaryAction.action,
                          ),
                        ),
                        child: Text(primaryAction.label),
                      )
                    else
                      SlButton(
                        key: const ValueKey('task_hub_banner_open_hub'),
                        onPressed: widget.onViewAll,
                        child: Text(context.t.actions.taskHub.openTaskHub),
                      ),
                    if (primary != null &&
                        secondaryAction != null &&
                        widget.onQuickAction != null)
                      SlButton(
                        buttonKey:
                            const ValueKey('task_hub_banner_secondary_action'),
                        variant: SlButtonVariant.outline,
                        onPressed: () => unawaited(
                          widget.onQuickAction!(
                            primary,
                            secondaryAction.action,
                          ),
                        ),
                        child: Text(secondaryAction.label),
                      ),
                    if (primary != null && widget.onOpenTodo != null)
                      SlButton(
                        buttonKey: const ValueKey('task_hub_banner_open_focus'),
                        variant: SlButtonVariant.outline,
                        onPressed: () => unawaited(widget.onOpenTodo!(primary)),
                        child: Text(context.t.actions.taskHub.openFocus),
                      ),
                    if (primary != null && primaryAction != null)
                      SlButton(
                        buttonKey: const ValueKey('task_hub_banner_view_all'),
                        variant: SlButtonVariant.outline,
                        onPressed: widget.onViewAll,
                        child: Text(context.t.actions.taskHub.openTaskHub),
                      ),
                  ],
                ),
                if (_expanded) ...[
                  SizedBox(height: actionsSpacingTop),
                  _BannerPreviewList(
                    snapshot: widget.snapshot,
                    checklistProgressByTodoId: widget.checklistProgressByTodoId,
                    onOpenTodo: widget.onOpenTodo,
                    onQuickAction: widget.onQuickAction,
                    onFeedback: widget.onFeedback,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fallbackSubtitle(BuildContext context) {
    final snapshot = widget.snapshot;
    if (!snapshot.isEmpty) {
      return context.t.actions.taskHub.wrapUpSubtitle(
        decide: snapshot.decide.length,
        done: snapshot.done.length,
      );
    }
    return context.t.actions.taskHub.noTasksSubtitle;
  }
}

class _BannerPreviewList extends StatelessWidget {
  const _BannerPreviewList({
    required this.snapshot,
    required this.checklistProgressByTodoId,
    required this.onOpenTodo,
    required this.onQuickAction,
    required this.onFeedback,
  });

  final TaskPrioritySnapshot snapshot;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  final Future<void> Function(TaskPriorityEntry entry)? onOpenTodo;
  final Future<void> Function(
      TaskPriorityEntry entry, TaskHubQuickAction action)? onQuickAction;
  final Future<void> Function(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  )? onFeedback;

  @override
  Widget build(BuildContext context) {
    final primaryTodoId = snapshot.primaryFocus?.todo.id;
    final previewEntries = snapshot.activeEntries
        .where((entry) => entry.todo.id != primaryTodoId)
        .take(4)
        .toList(growable: false);
    if (previewEntries.isEmpty) {
      return const SizedBox(
        key: ValueKey('task_hub_preview_list'),
        child: SizedBox.shrink(),
      );
    }
    return Column(
      key: const ValueKey('task_hub_preview_list'),
      children: [
        for (final entry in previewEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TaskHubEntryCard(
              key: ValueKey('task_hub_banner_item_${entry.todo.id}'),
              entry: entry,
              checklistProgressByTodoId: checklistProgressByTodoId,
              onOpenTodo: () =>
                  onOpenTodo == null ? null : unawaited(onOpenTodo!(entry)),
              onQuickAction: onQuickAction == null
                  ? (_) {}
                  : (action) => unawaited(onQuickAction!(entry, action)),
              onFeedback: onFeedback == null
                  ? null
                  : (feedback) => unawaited(onFeedback!(entry, feedback)),
              showPriorityControls: false,
            ),
          ),
      ],
    );
  }
}
