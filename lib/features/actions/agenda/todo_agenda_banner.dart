import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';

class TodoAgendaBanner extends StatefulWidget {
  const TodoAgendaBanner({
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.previewTodos,
    this.collapseSignal = 0,
    this.onViewAll,
    super.key,
  });

  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final List<Todo> previewTodos;
  final int collapseSignal;
  final VoidCallback? onViewAll;

  @override
  State<TodoAgendaBanner> createState() => _TodoAgendaBannerState();
}

class _TodoAgendaBannerState extends State<TodoAgendaBanner> {
  static const _kDoneDotColor = Color(0xFF22C55E);
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
  void didUpdateWidget(covariant TodoAgendaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseSignal == oldWidget.collapseSignal) return;
    _cancelAutoCollapseTimer();
    if (_expanded) setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _cancelAutoCollapseTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasDue = widget.dueCount > 0;
    final hasUpcoming = widget.upcomingCount > 0;
    if (!hasDue && !hasUpcoming) {
      _cancelAutoCollapseTimer();
      return const SizedBox.shrink();
    }

    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final todos = widget.previewTodos;
    final summaryText = hasDue
        ? context.t.actions.agenda
            .summary(due: widget.dueCount, overdue: widget.overdueCount)
        : context.t.actions.agenda.upcomingSummary(count: widget.upcomingCount);
    final nextTitle = todos.isEmpty ? null : todos.first.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SlSurface(
        color: tokens.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('todo_agenda_banner'),
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
                          summaryText,
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
            if (_expanded && todos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SlSurface(
                key: const ValueKey('todo_agenda_preview_list'),
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < todos.length; i++) ...[
                      _TodoPreviewRow(
                        key: ValueKey('todo_agenda_preview_${todos[i].id}'),
                        todo: todos[i],
                      ),
                      if (i != todos.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: tokens.borderSubtle.withOpacity(0.9),
                        ),
                    ],
                  ],
                ),
              ),
              if (widget.onViewAll != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('todo_agenda_view_all'),
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
}

final class _TodoPreviewRow extends StatelessWidget {
  const _TodoPreviewRow({required this.todo, super.key});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isDone = todo.status == 'done';
    final dueAtMs = todo.dueAtMs;
    final dueAtLocal = dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final isOverdue =
        !isDone && dueAtLocal != null && dueAtLocal.isBefore(DateTime.now());

    final dueText = dueAtLocal == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(dueAtLocal),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isDone
                  ? _TodoAgendaBannerState._kDoneDotColor
                  : (isOverdue ? colorScheme.error : colorScheme.primary),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              todo.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (dueText != null) ...[
            const SizedBox(width: 10),
            Text(
              dueText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: tokens.border,
          ),
        ],
      ),
    );
  }
}
