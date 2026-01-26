import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_icon_button.dart';
import '../../../ui/sl_tokens.dart';
import '../time/date_time_picker_dialog.dart';
import '../todo/todo_detail_page.dart';
import '../todo/todo_history_page.dart';

class TodoAgendaPage extends StatefulWidget {
  const TodoAgendaPage({super.key});

  @override
  State<TodoAgendaPage> createState() => _TodoAgendaPageState();
}

class _TodoAgendaPageState extends State<TodoAgendaPage> {
  Future<List<Todo>>? _todosFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _todosFuture ??= _loadTodos();
  }

  Future<List<Todo>> _loadTodos() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final todos = await backend.listTodos(sessionKey);

    final filtered = todos
        .where((t) =>
            t.dueAtMs != null && t.status != 'done' && t.status != 'dismissed')
        .toList(growable: false);
    filtered.sort((a, b) => a.dueAtMs!.compareTo(b.dueAtMs!));
    return filtered;
  }

  void _refresh() {
    setState(() {
      _todosFuture = _loadTodos();
    });
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  String _nextStatusForTap(String status) => switch (status) {
        'inbox' => 'in_progress',
        'open' => 'in_progress',
        'in_progress' => 'done',
        _ => 'open',
      };

  Future<void> _setStatus(Todo todo, String newStatus) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: newStatus,
    );
    if (!mounted) return;
    _refresh();
  }

  Future<void> _editDue(Todo todo) async {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return;

    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final nowLocal = DateTime.now();
    final picked = await showSlDateTimePickerDialog(
      context,
      initialLocal: dueAtLocal,
      firstDate: DateTime(nowLocal.year - 1),
      lastDate: DateTime(nowLocal.year + 3),
      title: context.t.actions.calendar.pickCustom,
      surfaceKey: ValueKey('todo_agenda_due_picker_${todo.id}'),
    );
    if (picked == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: picked.toUtc().millisecondsSinceEpoch,
      status: todo.status,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: todo.reviewStage,
      nextReviewAtMs: todo.nextReviewAtMs,
      lastReviewAtMs: todo.lastReviewAtMs,
    );
    if (!mounted) return;
    _refresh();
  }

  String? _formatDue(BuildContext context, Todo todo) {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return null;
    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(dueAtLocal);
    final time =
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dueAtLocal));
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return Scaffold(
      key: const ValueKey('todo_agenda_page'),
      appBar: AppBar(
        title: Text(context.t.actions.agenda.title),
        actions: [
          IconButton(
            tooltip: context.t.actions.history.title,
            icon: const Icon(Icons.history_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TodoHistoryPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<List<Todo>>(
            future: _todosFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    context.t.errors.loadFailed(error: '${snapshot.error}'),
                  ),
                );
              }

              final todos = snapshot.data ?? const <Todo>[];
              if (todos.isEmpty) {
                return Center(child: Text(context.t.actions.agenda.empty));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: todos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  final dueText = _formatDue(context, todo);
                  final dueAtMs = todo.dueAtMs;
                  final dueAtLocal = dueAtMs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          dueAtMs,
                          isUtc: true,
                        ).toLocal();
                  final overdue =
                      dueAtLocal != null && dueAtLocal.isBefore(DateTime.now());
                  final radius = BorderRadius.circular(tokens.radiusLg);
                  final colorScheme = Theme.of(context).colorScheme;
                  final overlay = MaterialStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(MaterialState.pressed)) {
                        return colorScheme.primary.withOpacity(0.12);
                      }
                      if (states.contains(MaterialState.hovered) ||
                          states.contains(MaterialState.focused)) {
                        return colorScheme.primary.withOpacity(0.08);
                      }
                      return null;
                    },
                  );

                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('todo_agenda_item_${todo.id}'),
                        borderRadius: radius,
                        overlayColor: overlay,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TodoDetailPage(initialTodo: todo),
                            ),
                          );
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: radius,
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: overdue
                                            ? colorScheme.error
                                            : colorScheme.primary,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        todo.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _TodoStatusButton(
                                      buttonKey: ValueKey(
                                        'todo_agenda_toggle_status_${todo.id}',
                                      ),
                                      label: _statusLabel(context, todo.status),
                                      onPressed: () => _setStatus(
                                        todo,
                                        _nextStatusForTap(todo.status),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SlIconButton(
                                      key: ValueKey(
                                        'todo_agenda_delete_${todo.id}',
                                      ),
                                      tooltip: context.t.common.actions.delete,
                                      icon: Icons.delete_outline_rounded,
                                      size: 38,
                                      iconSize: 18,
                                      color: colorScheme.error,
                                      overlayBaseColor: colorScheme.error,
                                      borderColor:
                                          colorScheme.error.withOpacity(
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.32
                                            : 0.22,
                                      ),
                                      onPressed: () =>
                                          _setStatus(todo, 'dismissed'),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 24,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                if (dueText != null) ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 20),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 520,
                                      ),
                                      child: _TodoDueChip(
                                        chipKey: ValueKey(
                                          'todo_agenda_due_${todo.id}',
                                        ),
                                        icon: overdue
                                            ? Icons.warning_rounded
                                            : Icons.schedule_rounded,
                                        label: dueText,
                                        highlight: overdue
                                            ? _DueChipHighlight.danger
                                            : _DueChipHighlight.neutral,
                                        onPressed: () => _editDue(todo),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _TodoStatusButton extends StatelessWidget {
  const _TodoStatusButton({
    required this.label,
    required this.onPressed,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;
    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return colorScheme.primary.withOpacity(0.18);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return colorScheme.primary.withOpacity(0.12);
      }
      return null;
    });

    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: tokens.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide(color: tokens.borderSubtle),
      ).copyWith(overlayColor: overlay),
      icon: Icon(
        Icons.swap_horiz_rounded,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _DueChipHighlight {
  neutral,
  danger,
}

final class _TodoDueChip extends StatelessWidget {
  const _TodoDueChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.highlight,
    this.chipKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final _DueChipHighlight highlight;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fg = highlight == _DueChipHighlight.danger
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final border = highlight == _DueChipHighlight.danger
        ? colorScheme.error.withOpacity(isDark ? 0.4 : 0.28)
        : tokens.borderSubtle.withOpacity(isDark ? 0.9 : 0.95);

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      final base = highlight == _DueChipHighlight.danger
          ? colorScheme.error
          : colorScheme.primary;
      if (states.contains(MaterialState.pressed)) {
        return base.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return base.withOpacity(0.12);
      }
      return null;
    });

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: OutlinedButton.icon(
        key: chipKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: tokens.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide(color: border),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: overlay),
        icon: Icon(icon, size: 16, color: fg),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
