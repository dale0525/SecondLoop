import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_actions.dart';
import 'task_hub_summary.dart';

class TaskHubBanner extends StatefulWidget {
  const TaskHubBanner({
    required this.summary,
    this.collapseSignal = 0,
    this.onViewAll,
    this.onQuickAction,
    super.key,
  });

  final TaskHubSummary summary;
  final int collapseSignal;
  final VoidCallback? onViewAll;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  State<TaskHubBanner> createState() => _TaskHubBannerState();
}

class _TaskHubBannerState extends State<TaskHubBanner> {
  static const _kAutoCollapseDelay = Duration(seconds: 10);

  var _expanded = false;
  Timer? _autoCollapseTimer;

  void _cancelAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = null;
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;

    setState(() => _expanded = expanded);
    _cancelAutoCollapseTimer();

    if (!expanded) return;
    _autoCollapseTimer = Timer(_kAutoCollapseDelay, () {
      if (!mounted) return;
      _setExpanded(false);
    });
  }

  @override
  void didUpdateWidget(covariant TaskHubBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseSignal == oldWidget.collapseSignal) return;
    _cancelAutoCollapseTimer();
    if (_expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  void dispose() {
    _cancelAutoCollapseTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary.isEmpty) {
      _cancelAutoCollapseTimer();
      return const SizedBox.shrink();
    }

    final summary = widget.summary;
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final headline = _collapsedHeadline(context, summary);
    final nextTitle = summary.scheduledPreviewTodos.isNotEmpty
        ? summary.scheduledPreviewTodos.first.title
        : summary.unscheduledPreviewTodos.isNotEmpty
            ? summary.unscheduledPreviewTodos.first.title
            : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SlSurface(
        color: tokens.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('task_hub_banner'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => _setExpanded(!_expanded),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      border: Border.all(color: tokens.borderSubtle),
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                    ),
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.checklist_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!_expanded && nextTitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            nextTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              SlSurface(
                key: const ValueKey('task_hub_preview_list'),
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.scheduledPreviewTodos.isNotEmpty)
                      _TaskHubSection(
                        title: context.t.actions.taskHub.scheduledSection,
                        todos: summary.scheduledPreviewTodos,
                        onQuickAction: widget.onQuickAction,
                      ),
                    if (summary.scheduledPreviewTodos.isNotEmpty &&
                        summary.unscheduledPreviewTodos.isNotEmpty)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: tokens.borderSubtle.withOpacity(0.9),
                      ),
                    if (summary.unscheduledPreviewTodos.isNotEmpty)
                      _TaskHubSection(
                        title: context.t.actions.taskHub.reviewSection,
                        todos: summary.unscheduledPreviewTodos,
                        onQuickAction: widget.onQuickAction,
                      ),
                  ],
                ),
              ),
              if (widget.onViewAll != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('task_hub_view_all'),
                    onPressed: widget.onViewAll,
                    child: Text(context.t.actions.agenda.viewAll),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _collapsedHeadline(BuildContext context, TaskHubSummary summary) {
    if (summary.overdueCount > 0) {
      return context.t.actions.agenda
          .summary(due: summary.dueCount, overdue: summary.overdueCount);
    }
    if (summary.dueReviewCount > 0) {
      return context.t.actions.reviewQueue
          .banner(count: summary.dueReviewCount);
    }
    final upcoming = context.t.actions.agenda.upcomingSummary(
      count: summary.upcomingCount,
    );
    final unscheduled = context.t.actions.agenda
        .undeterminedSummary(count: summary.unscheduledCount);
    return '$upcoming · $unscheduled';
  }
}

class _TaskHubSection extends StatelessWidget {
  const _TaskHubSection({
    required this.title,
    required this.todos,
    required this.onQuickAction,
  });

  final String title;
  final List<Todo> todos;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          for (final todo in todos)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _TaskHubTodoRow(
                todo: todo,
                onQuickAction: onQuickAction,
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskHubTodoRow extends StatelessWidget {
  const _TaskHubTodoRow({required this.todo, required this.onQuickAction});

  final Todo todo;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  Widget build(BuildContext context) {
    final dueAtMs = todo.dueAtMs;
    final dueAtLocal = dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          todo.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (dueAtLocal != null)
          Text(
            MaterialLocalizations.of(context).formatShortDate(dueAtLocal),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _QuickActionButton(
              key: ValueKey('task_hub_quick_${todo.id}_today'),
              label: context.t.actions.taskHub.actions.today,
              onPressed: onQuickAction == null
                  ? null
                  : () => onQuickAction!(todo, TaskHubQuickAction.today),
            ),
            _QuickActionButton(
              key: ValueKey('task_hub_quick_${todo.id}_tomorrow'),
              label: context.t.actions.taskHub.actions.tomorrow,
              onPressed: onQuickAction == null
                  ? null
                  : () => onQuickAction!(todo, TaskHubQuickAction.tomorrow),
            ),
            _QuickActionButton(
              key: ValueKey('task_hub_quick_${todo.id}_this_week'),
              label: context.t.actions.taskHub.actions.thisWeek,
              onPressed: onQuickAction == null
                  ? null
                  : () => onQuickAction!(todo, TaskHubQuickAction.thisWeek),
            ),
            _QuickActionButton(
              key: ValueKey('task_hub_quick_${todo.id}_later'),
              label: context.t.actions.taskHub.actions.later,
              onPressed: onQuickAction == null
                  ? null
                  : () => onQuickAction!(todo, TaskHubQuickAction.later),
            ),
            _QuickActionButton(
              key: ValueKey('task_hub_quick_${todo.id}_done'),
              label: context.t.actions.taskHub.actions.done,
              onPressed: onQuickAction == null
                  ? null
                  : () => onQuickAction!(todo, TaskHubQuickAction.done),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
