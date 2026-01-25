import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';

class TodoAgendaBanner extends StatefulWidget {
  const TodoAgendaBanner({
    required this.dueCount,
    required this.overdueCount,
    required this.previewTodos,
    this.onViewAll,
    super.key,
  });

  final int dueCount;
  final int overdueCount;
  final List<Todo> previewTodos;
  final VoidCallback? onViewAll;

  @override
  State<TodoAgendaBanner> createState() => _TodoAgendaBannerState();
}

class _TodoAgendaBannerState extends State<TodoAgendaBanner> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.dueCount <= 0) return const SizedBox.shrink();

    final tokens = SlTokens.of(context);
    final todos = widget.previewTodos;
    final summaryText = context.t.actions.agenda
        .summary(due: widget.dueCount, overdue: widget.overdueCount);
    final nextTitle = todos.isEmpty ? null : todos.first.title;
    final collapsedLine =
        nextTitle == null ? summaryText : '$summaryText · $nextTitle';
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
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  const Icon(Icons.checklist_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      collapsedLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_expanded && todos.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final todo in todos)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SlSurface(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      todo.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              if (widget.onViewAll != null) ...[
                const SizedBox(height: 10),
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
