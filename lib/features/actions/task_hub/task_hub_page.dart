import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import 'task_hub_quick_actions.dart';
import 'task_hub_summary.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';
import '../todo/todo_detail_page.dart';

class TaskHubPage extends StatefulWidget {
  const TaskHubPage({super.key});

  @override
  State<TaskHubPage> createState() => _TaskHubPageState();
}

class _TaskHubPageState extends State<TaskHubPage> {
  Future<TaskHubSummary>? _summaryFuture;
  TaskHubUndoTicket? _undoTicket;
  Timer? _quickActionSnackAutoDismissTimer;

  @override
  void dispose() {
    _quickActionSnackAutoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summaryFuture ??= _loadSummary();
  }

  Future<TaskHubSummary> _loadSummary() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    final nowLocal = DateTime.now();
    late final ActionsSettings settings;
    try {
      settings = await ActionsSettingsStore.load();
    } catch (_) {
      settings = const ActionsSettings(
        morningTime: TimeOfDay(hour: 8, minute: 0),
        dayEndTime: TimeOfDay(hour: 21, minute: 0),
        weeklyReviewTime: TimeOfDay(hour: 21, minute: 0),
      );
    }

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return const TaskHubSummary.empty();
    }

    final normalizedTodos = <Todo>[];
    var didMutate = false;
    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) {
        normalizedTodos.add(todo);
        continue;
      }

      final scheduledLocal =
          DateTime.fromMillisecondsSinceEpoch(nextMs, isUtc: true).toLocal();
      final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
        stage: stage,
        scheduledAtLocal: scheduledLocal,
        nowLocal: nowLocal,
        settings: settings,
      );
      if (rolled.stage == stage && rolled.nextReviewAtLocal == scheduledLocal) {
        normalizedTodos.add(todo);
        continue;
      }

      try {
        final updated = await backend.upsertTodo(
          sessionKey,
          id: todo.id,
          title: todo.title,
          dueAtMs: todo.dueAtMs,
          status: todo.status,
          sourceEntryId: todo.sourceEntryId,
          reviewStage: rolled.stage,
          nextReviewAtMs:
              rolled.nextReviewAtLocal.toUtc().millisecondsSinceEpoch,
          lastReviewAtMs: todo.lastReviewAtMs,
        );
        normalizedTodos.add(updated);
        didMutate = true;
      } catch (_) {
        normalizedTodos.add(todo);
      }
    }

    if (didMutate) {
      syncEngine?.notifyLocalMutation();
    }

    return TaskHubSummary.fromTodos(
      normalizedTodos,
      nowLocal: nowLocal,
      scheduledPreviewLimit: 4,
      unscheduledPreviewLimit: 4,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _summaryFuture = _loadSummary();
    });
  }

  Future<void> _openTodoDetail(Todo todo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TodoDetailPage(initialTodo: todo),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  String _actionLabel(TaskHubQuickAction action) => switch (action) {
        TaskHubQuickAction.today => context.t.actions.taskHub.actions.today,
        TaskHubQuickAction.tomorrow =>
          context.t.actions.taskHub.actions.tomorrow,
        TaskHubQuickAction.thisWeek =>
          context.t.actions.taskHub.actions.thisWeek,
        TaskHubQuickAction.later => context.t.actions.taskHub.actions.later,
        TaskHubQuickAction.done => context.t.actions.taskHub.actions.done,
      };

  Future<void> _applyQuickAction(Todo todo, TaskHubQuickAction action) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: sessionKey,
    );

    late final TaskHubUndoTicket ticket;
    try {
      final maybeTicket = await controller.apply(todo, action);
      if (maybeTicket == null) return;
      ticket = maybeTicket;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.t.errors.saveFailed(error: '$e')),
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }

    if (!mounted) return;

    _undoTicket = ticket;
    final snackMessage = context.t.actions.taskHub.snackActionApplied(
      action: _actionLabel(action),
      title: ticket.updatedTodo.title,
    );
    final undoLabel = context.t.common.actions.undo;
    syncEngine?.notifyLocalMutation();
    await _refresh();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    final snackController = messenger?.showSnackBar(
      SnackBar(
        content: Text(snackMessage),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () async {
            if (_undoTicket != ticket) return;
            try {
              await controller.undo(ticket);
              if (!mounted) return;
              if (_undoTicket == ticket) {
                _undoTicket = null;
              }
              syncEngine?.notifyLocalMutation();
              await _refresh();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(context.t.errors.saveFailed(error: '$e')),
                    duration: const Duration(seconds: 3),
                  ),
                );
            }
          },
        ),
      ),
    );
    if (snackController == null) return;
    final autoDismissTimer = Timer(
      const Duration(seconds: 3),
      snackController.close,
    );
    _quickActionSnackAutoDismissTimer = autoDismissTimer;

    unawaited(
      snackController.closed.then((_) {
        autoDismissTimer.cancel();
        if (identical(_quickActionSnackAutoDismissTimer, autoDismissTimer)) {
          _quickActionSnackAutoDismissTimer = null;
        }
        if (!mounted) return;
        if (_undoTicket == ticket) {
          _undoTicket = null;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('task_hub_page'),
      appBar: AppBar(
        title: Text(context.t.actions.taskHub.title),
        actions: [
          IconButton(
            onPressed: () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.t.common.actions.refresh,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<TaskHubSummary>(
            future: _summaryFuture,
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

              final summary = snapshot.data ?? const TaskHubSummary.empty();
              if (summary.isEmpty) {
                return Center(child: Text(context.t.actions.agenda.empty));
              }

              final scheduled = <Todo>[
                ...summary.dueTodos,
                ...summary.upcomingTodos,
              ];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TaskHubPageSection(
                    key: const ValueKey('task_hub_page_section_scheduled'),
                    title: context.t.actions.taskHub.scheduledSection,
                    todos: scheduled,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                  ),
                  _TaskHubPageSection(
                    key: const ValueKey('task_hub_page_section_review'),
                    title: context.t.actions.taskHub.reviewSection,
                    todos: summary.dueReviewTodos,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                  ),
                  _TaskHubPageSection(
                    key: const ValueKey('task_hub_page_section_unscheduled'),
                    title: context.t.actions.taskHub.unscheduledSection,
                    todos: summary.unscheduledTodos,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TaskHubPageSection extends StatelessWidget {
  const _TaskHubPageSection({
    required this.title,
    required this.todos,
    required this.onQuickAction,
    required this.onOpenTodo,
    super.key,
  });

  final String title;
  final List<Todo> todos;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)
      onQuickAction;
  final Future<void> Function(Todo todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SlSurface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: tokens.borderSubtle.withOpacity(0.9),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      todos.length.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < todos.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == todos.length - 1 ? 0 : 8),
                child: _TaskHubPageTodoRow(
                  todo: todos[i],
                  onQuickAction: onQuickAction,
                  onOpenTodo: onOpenTodo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskHubPageTodoRow extends StatelessWidget {
  const _TaskHubPageTodoRow({
    required this.todo,
    required this.onQuickAction,
    required this.onOpenTodo,
  });

  final Todo todo;
  final Future<void> Function(Todo todo, TaskHubQuickAction action)
      onQuickAction;
  final Future<void> Function(Todo todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final dueAtMs = todo.dueAtMs;
    final dueAtLocal = dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final dueAtText = dueAtLocal == null
        ? null
        : '${MaterialLocalizations.of(context).formatShortDate(dueAtLocal)} '
            '${MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(dueAtLocal),
            alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
          )}';
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final overdue = dueAtLocal != null &&
        dueAtLocal.isBefore(DateTime.now()) &&
        todo.status != 'done' &&
        todo.status != 'dismissed';
    final dotColor = todo.status == 'done'
        ? const Color(0xFF22C55E)
        : overdue
            ? colorScheme.error
            : colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface2.withOpacity(0.55),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('task_hub_page_item_${todo.id}'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: () => unawaited(onOpenTodo(todo)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (dueAtText != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      dueAtText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TaskHubPageQuickButton(
                  key: ValueKey('task_hub_page_quick_${todo.id}_today'),
                  icon: Icons.today_rounded,
                  label: context.t.actions.taskHub.actions.today,
                  onPressed: () =>
                      onQuickAction(todo, TaskHubQuickAction.today),
                ),
                _TaskHubPageQuickButton(
                  key: ValueKey('task_hub_page_quick_${todo.id}_tomorrow'),
                  icon: Icons.event_rounded,
                  label: context.t.actions.taskHub.actions.tomorrow,
                  onPressed: () =>
                      onQuickAction(todo, TaskHubQuickAction.tomorrow),
                ),
                _TaskHubPageQuickButton(
                  key: ValueKey('task_hub_page_quick_${todo.id}_this_week'),
                  icon: Icons.date_range_rounded,
                  label: context.t.actions.taskHub.actions.thisWeek,
                  onPressed: () =>
                      onQuickAction(todo, TaskHubQuickAction.thisWeek),
                ),
                _TaskHubPageQuickButton(
                  key: ValueKey('task_hub_page_quick_${todo.id}_later'),
                  icon: Icons.schedule_send_rounded,
                  label: context.t.actions.taskHub.actions.later,
                  onPressed: () =>
                      onQuickAction(todo, TaskHubQuickAction.later),
                ),
                _TaskHubPageQuickButton(
                  key: ValueKey('task_hub_page_quick_${todo.id}_done'),
                  icon: Icons.check_rounded,
                  label: context.t.actions.taskHub.actions.done,
                  onPressed: () => onQuickAction(todo, TaskHubQuickAction.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskHubPageQuickButton extends StatelessWidget {
  const _TaskHubPageQuickButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final borderRadius = BorderRadius.circular(99);
    final baseStyle = ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(Size(0, 30)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      textStyle: MaterialStatePropertyAll(
        Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: baseStyle.copyWith(
        side: MaterialStatePropertyAll(
          BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
        ),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label),
    );
  }
}
