import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_action_layout.dart';
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
  static const _kExpandedPreviewMaxHeightFactor = 0.5;

  var _expanded = false;

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
  }

  @override
  void didUpdateWidget(covariant TaskHubBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseSignal == oldWidget.collapseSignal) return;
    if (_expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary.isEmpty) {
      return const SizedBox.shrink();
    }

    final summary = widget.summary;
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final expandedPreviewMaxHeight =
        MediaQuery.sizeOf(context).height * _kExpandedPreviewMaxHeightFactor;

    final headline = _collapsedHeadline(context, summary);
    final nextTitle = summary.scheduledPreviewTodos.isNotEmpty
        ? summary.scheduledPreviewTodos.first.title
        : summary.unscheduledPreviewTodos.isNotEmpty
            ? summary.unscheduledPreviewTodos.first.title
            : null;
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final dueReviewPreview = summary.unscheduledPreviewTodos
        .where(
          (todo) =>
              todo.reviewStage != null &&
              todo.nextReviewAtMs != null &&
              todo.nextReviewAtMs! <= nowUtcMs,
        )
        .toList(growable: false);
    final unscheduledPreview = summary.unscheduledPreviewTodos
        .where(
          (todo) =>
              !dueReviewPreview.any((candidate) => candidate.id == todo.id),
        )
        .toList(growable: false);

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
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: expandedPreviewMaxHeight),
                child: SlSurface(
                  key: const ValueKey('task_hub_preview_list'),
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summary.scheduledPreviewTodos.isNotEmpty)
                          _TaskHubSection(
                            title: context.t.actions.taskHub.scheduledSection,
                            todos: summary.scheduledPreviewTodos,
                            sectionKind: _TaskHubBannerSectionKind.scheduled,
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
                          _TaskHubMergedUnscheduledSection(
                            dueReviewTodos: dueReviewPreview,
                            unscheduledTodos: unscheduledPreview,
                            onQuickAction: widget.onQuickAction,
                          ),
                      ],
                    ),
                  ),
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
    if (summary.dueCount > 0) {
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

enum _TaskHubBannerSectionKind {
  scheduled,
  dueReview,
  unscheduled,
}

class _TaskHubSection extends StatelessWidget {
  const _TaskHubSection({
    required this.title,
    required this.todos,
    required this.sectionKind,
    required this.onQuickAction,
  });

  final String title;
  final List<Todo> todos;
  final _TaskHubBannerSectionKind sectionKind;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < todos.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 6 : 8),
              child: _TaskHubTodoRow(
                todo: todos[i],
                sectionKind: sectionKind,
                onQuickAction: onQuickAction,
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskHubMergedUnscheduledSection extends StatelessWidget {
  const _TaskHubMergedUnscheduledSection({
    required this.dueReviewTodos,
    required this.unscheduledTodos,
    required this.onQuickAction,
  });

  final List<Todo> dueReviewTodos;
  final List<Todo> unscheduledTodos;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  Widget build(BuildContext context) {
    if (dueReviewTodos.isEmpty && unscheduledTodos.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.actions.taskHub.unscheduledSection,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          if (dueReviewTodos.isNotEmpty) ...[
            _TaskHubSubheader(
              key: const ValueKey('task_hub_banner_section_unscheduled_review'),
              title: context.t.actions.taskHub.reviewSection,
              count: dueReviewTodos.length,
            ),
            for (var i = 0; i < dueReviewTodos.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 6 : 8),
                child: _TaskHubTodoRow(
                  todo: dueReviewTodos[i],
                  sectionKind: _TaskHubBannerSectionKind.dueReview,
                  onQuickAction: onQuickAction,
                ),
              ),
          ],
          if (dueReviewTodos.isNotEmpty && unscheduledTodos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle.withOpacity(0.9),
            ),
            const SizedBox(height: 8),
          ],
          if (unscheduledTodos.isNotEmpty) ...[
            KeyedSubtree(
              key: const ValueKey('task_hub_banner_section_unscheduled_plain'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < unscheduledTodos.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                      child: _TaskHubTodoRow(
                        todo: unscheduledTodos[i],
                        sectionKind: _TaskHubBannerSectionKind.unscheduled,
                        onQuickAction: onQuickAction,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskHubSubheader extends StatelessWidget {
  const _TaskHubSubheader({
    required this.title,
    required this.count,
    super.key,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: tokens.borderSubtle.withOpacity(0.9),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              count.toString(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskHubTodoRow extends StatelessWidget {
  const _TaskHubTodoRow({
    required this.todo,
    required this.sectionKind,
    required this.onQuickAction,
  });

  final Todo todo;
  final _TaskHubBannerSectionKind sectionKind;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)?
      onQuickAction;

  @override
  Widget build(BuildContext context) {
    final dueAtMs = todo.dueAtMs;
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final dueAtLocal = dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final dueAtText = dueAtLocal == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(dueAtLocal);
    final overdue = dueAtLocal != null && dueAtLocal.isBefore(DateTime.now());
    final dotColor = overdue ? colorScheme.error : colorScheme.primary;
    final actionLayout = buildTaskHubQuickActionLayout(
      context,
      todo: todo,
      sectionKind: _resolveQuickActionSectionKind(),
      dueAtLocal: dueAtLocal,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface2.withOpacity(0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tokens.borderSubtle.withOpacity(0.9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (dueAtText != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dueAtText,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actionLayout.$1)
                  _QuickActionButton(
                    key: ValueKey(
                        'task_hub_quick_${todo.id}_${action.action.name}'),
                    icon: action.icon,
                    label: action.label,
                    tone: action.tone,
                    onPressed: onQuickAction == null
                        ? null
                        : () => onQuickAction!(todo, action.action),
                  ),
                if (actionLayout.$2.isNotEmpty)
                  _QuickActionMenu(
                    key: ValueKey('task_hub_quick_${todo.id}_more'),
                    items: actionLayout.$2,
                    onSelected: onQuickAction == null
                        ? null
                        : (action) => unawaited(onQuickAction!(todo, action)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TaskHubQuickActionSectionKind _resolveQuickActionSectionKind() {
    return switch (sectionKind) {
      _TaskHubBannerSectionKind.scheduled =>
        TaskHubQuickActionSectionKind.scheduled,
      _TaskHubBannerSectionKind.dueReview =>
        TaskHubQuickActionSectionKind.dueReview,
      _TaskHubBannerSectionKind.unscheduled =>
        TaskHubQuickActionSectionKind.unscheduled,
    };
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    this.tone = TaskHubQuickActionTone.secondary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final TaskHubQuickActionTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final baseStyle = ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(Size(0, 40)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      textStyle: MaterialStatePropertyAll(
        Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );

    if (tone == TaskHubQuickActionTone.primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: baseStyle,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: baseStyle.copyWith(
        side: MaterialStatePropertyAll(
          BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _QuickActionMenu extends StatelessWidget {
  const _QuickActionMenu({
    required this.items,
    required this.onSelected,
    super.key,
  });

  final List<TaskHubQuickActionItem> items;
  final ValueChanged<TaskHubQuickAction>? onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return PopupMenuButton<TaskHubQuickAction>(
      tooltip: context.t.actions.taskHub.actions.more,
      onSelected: onSelected,
      enabled: onSelected != null,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Icon(Icons.more_horiz_rounded, size: 18),
          ),
        ),
      ),
    );
  }
}
