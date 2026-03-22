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
    final hasAiReason = widget.snapshot.hasAiEnhancement &&
        (primary?.reasonText ?? '').isNotEmpty;
    final aiSourceLabel = _aiSourceLabel(context, widget.snapshot);
    final outerPadding = widget.compact
        ? const EdgeInsets.fromLTRB(12, 6, 12, 4)
        : const EdgeInsets.fromLTRB(12, 12, 12, 8);
    final innerPadding = widget.compact ? 8.0 : 12.0;
    final headerSpacing = widget.compact ? 3.0 : 6.0;
    final actionsSpacingTop = widget.compact ? 6.0 : 12.0;
    final compactCollapsed = widget.compact && !_expanded;
    final showAiSourceLabel =
        aiSourceLabel != null && (!widget.compact || _expanded);
    final showSummaryChips = !widget.compact;
    final showAiHint =
        widget.showAiUpgradeHint && !hasAiReason && !widget.compact;
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
    final showQuickPair = !compactCollapsed &&
        primary != null &&
        primaryAction != null &&
        widget.onQuickAction != null;
    final showOpenFocusAction = !widget.compact && widget.onOpenTodo != null;
    final showNavigationActions = !compactCollapsed &&
        primary != null &&
        (showOpenFocusAction || widget.onViewAll != null);
    final showOpenHubAction = !compactCollapsed && primary == null;
    return Padding(
      padding: outerPadding,
      child: SlSurface(
        key: const ValueKey('task_hub_banner'),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _expanded = !_expanded);
          },
          child: Padding(
            padding: EdgeInsets.all(innerPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                if (showAiSourceLabel) ...[
                  SizedBox(height: headerSpacing),
                  Text(
                    aiSourceLabel,
                    key: const ValueKey('task_hub_banner_ai_source'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                SizedBox(height: headerSpacing),
                Text(
                  primary?.todo.title ??
                      context.t.actions.taskHub.wrapUpHeadline,
                  maxLines: widget.compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                SizedBox(height: headerSpacing),
                Text(
                  primary?.reasonText ?? _fallbackSubtitle(context),
                  maxLines: compactCollapsed ? 1 : (widget.compact ? 2 : 3),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (showSummaryChips && !widget.snapshot.isEmpty) ...[
                  SizedBox(height: headerSpacing + 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _BannerStatChip(
                        label: context.t.actions.taskHub.scheduledSection,
                        value: widget.snapshot.upcomingDisplayCount,
                        tone: _BannerStatTone.nextUp,
                      ),
                      _BannerStatChip(
                        label: context.t.actions.taskHub.unscheduledSection,
                        value: widget.snapshot.backlogDisplayCount,
                        tone: _BannerStatTone.backlog,
                      ),
                      _BannerStatChip(
                        label: context.t.actions.taskHub.doneSection,
                        value: widget.snapshot.done.length,
                        tone: _BannerStatTone.done,
                      ),
                    ],
                  ),
                ],
                if (showAiHint) ...[
                  SizedBox(height: headerSpacing),
                  Text(
                    context.t.actions.taskHub.aiUpgradeHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
                if (!compactCollapsed) ...[
                  SizedBox(height: actionsSpacingTop),
                  if (showQuickPair) ...[
                    DecoratedBox(
                      key: const ValueKey('task_hub_banner_quick_pair'),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(widget.compact ? 0.28 : 0.4),
                        borderRadius: BorderRadius.circular(tokens.radiusLg),
                        border: Border.all(
                          color: tokens.borderSubtle.withOpacity(0.8),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: SlButton(
                                key: const ValueKey(
                                    'task_hub_banner_primary_action'),
                                onPressed: () => unawaited(
                                  widget.onQuickAction!(
                                    primary,
                                    primaryAction.action,
                                  ),
                                ),
                                child: Text(primaryAction.label),
                              ),
                            ),
                            if (secondaryAction != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: SlButton(
                                  buttonKey: const ValueKey(
                                      'task_hub_banner_secondary_action'),
                                  variant: SlButtonVariant.outline,
                                  onPressed: () => unawaited(
                                    widget.onQuickAction!(
                                      primary,
                                      secondaryAction.action,
                                    ),
                                  ),
                                  child: Text(secondaryAction.label),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (showNavigationActions) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (showOpenFocusAction)
                            SlButton(
                              buttonKey:
                                  const ValueKey('task_hub_banner_open_focus'),
                              variant: SlButtonVariant.outline,
                              onPressed: () =>
                                  unawaited(widget.onOpenTodo!(primary)),
                              child: Text(context.t.actions.taskHub.openFocus),
                            ),
                          if (widget.onViewAll != null)
                            SlButton(
                              buttonKey:
                                  const ValueKey('task_hub_banner_view_all'),
                              variant: SlButtonVariant.outline,
                              onPressed: widget.onViewAll,
                              child:
                                  Text(context.t.actions.taskHub.openTaskHub),
                            ),
                        ],
                      ),
                    ],
                  ] else if (primary != null && showNavigationActions)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (showOpenFocusAction)
                          SlButton(
                            buttonKey:
                                const ValueKey('task_hub_banner_open_focus'),
                            variant: SlButtonVariant.outline,
                            onPressed: () =>
                                unawaited(widget.onOpenTodo!(primary)),
                            child: Text(context.t.actions.taskHub.openFocus),
                          ),
                        if (widget.onViewAll != null)
                          SlButton(
                            buttonKey:
                                const ValueKey('task_hub_banner_view_all'),
                            variant: SlButtonVariant.outline,
                            onPressed: widget.onViewAll,
                            child: Text(context.t.actions.taskHub.openTaskHub),
                          ),
                      ],
                    )
                  else if (showOpenHubAction)
                    SlButton(
                      key: const ValueKey('task_hub_banner_open_hub'),
                      onPressed: widget.onViewAll,
                      child: Text(context.t.actions.taskHub.openTaskHub),
                    ),
                  if (_expanded) ...[
                    SizedBox(height: actionsSpacingTop),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: widget.compact ? 112 : 360,
                      ),
                      child: SingleChildScrollView(
                        child: _BannerPreviewList(
                          snapshot: widget.snapshot,
                          checklistProgressByTodoId:
                              widget.checklistProgressByTodoId,
                          onOpenTodo: widget.onOpenTodo,
                          onQuickAction: widget.onQuickAction,
                          onFeedback: widget.onFeedback,
                          compact: widget.compact,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _aiSourceLabel(
    BuildContext context,
    TaskPrioritySnapshot snapshot,
  ) {
    return switch (snapshot.enhancementSource) {
      TaskPriorityEnhancementSource.none => null,
      TaskPriorityEnhancementSource.aiLive =>
        context.t.actions.taskHub.aiInsightLive,
      TaskPriorityEnhancementSource.aiSharedCache =>
        context.t.actions.taskHub.aiInsightShared,
      TaskPriorityEnhancementSource.aiLocalCache =>
        context.t.actions.taskHub.aiInsightCached,
    };
  }

  String _fallbackSubtitle(BuildContext context) {
    final snapshot = widget.snapshot;
    if (!snapshot.isEmpty) {
      return context.t.actions.taskHub.wrapUpSubtitle(
        upcoming: snapshot.upcomingDisplayCount,
        backlog: snapshot.backlogDisplayCount,
        done: snapshot.done.length,
      );
    }
    return context.t.actions.taskHub.noTasksSubtitle;
  }
}

class _BannerStatChip extends StatelessWidget {
  const _BannerStatChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final int value;
  final _BannerStatTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = switch (tone) {
      _BannerStatTone.nextUp => (
          scheme.secondary,
          scheme.secondaryContainer.withOpacity(0.62),
          scheme.secondary.withOpacity(0.18),
        ),
      _BannerStatTone.backlog => (
          scheme.tertiary,
          scheme.tertiaryContainer.withOpacity(0.62),
          scheme.tertiary.withOpacity(0.18),
        ),
      _BannerStatTone.done => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest.withOpacity(0.42),
          scheme.outlineVariant.withOpacity(0.38),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.$3),
      ),
      child: Text(
        <String>[label, value.toString()].join(' '),
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.$1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _BannerStatTone { nextUp, backlog, done }

class _BannerPreviewList extends StatelessWidget {
  const _BannerPreviewList({
    required this.snapshot,
    required this.checklistProgressByTodoId,
    required this.onOpenTodo,
    required this.onQuickAction,
    required this.onFeedback,
    required this.compact,
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
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primaryTodoId = snapshot.primaryFocus?.todo.id;
    final previewEntries = snapshot.activeEntries
        .where(
          (entry) =>
              compact ||
              primaryTodoId == null ||
              entry.todo.id != primaryTodoId,
        )
        .take(compact ? 2 : 4)
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
