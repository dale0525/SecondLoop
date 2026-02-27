import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import 'task_hub_quick_actions.dart';
import 'task_hub_page_sections.dart';
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
  static const _kDonePageSize = 20;

  Future<TaskHubSummary>? _summaryFuture;
  TaskHubUndoTicket? _undoTicket;
  Timer? _quickActionSnackAutoDismissTimer;
  ScaffoldMessengerState? _quickActionSnackMessenger;
  Object? _quickActionSnackToken;
  var _doneVisibleCount = _kDonePageSize;

  @override
  void dispose() {
    if (_quickActionSnackToken != null) {
      _quickActionSnackMessenger?.hideCurrentSnackBar();
    }
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    _quickActionSnackMessenger = null;
    _quickActionSnackToken = null;
    _undoTicket = null;
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
      _doneVisibleCount = _kDonePageSize;
    });
  }

  void _loadMoreDone(int totalDoneCount) {
    if (_doneVisibleCount >= totalDoneCount) return;
    setState(() {
      _doneVisibleCount = math.min(
        _doneVisibleCount + _kDonePageSize,
        totalDoneCount,
      );
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
        TaskHubQuickAction.tonight => context.t.actions.taskHub.actions.tonight,
        TaskHubQuickAction.tomorrow =>
          context.t.actions.taskHub.actions.tomorrow,
        TaskHubQuickAction.pauseTomorrow =>
          context.t.actions.taskHub.actions.pauseTomorrow,
        TaskHubQuickAction.thisWeek =>
          context.t.actions.taskHub.actions.thisWeek,
        TaskHubQuickAction.later => context.t.actions.taskHub.actions.later,
        TaskHubQuickAction.start => context.t.actions.taskHub.actions.start,
        TaskHubQuickAction.moveToInbox =>
          context.t.actions.taskHub.actions.moveToInbox,
        TaskHubQuickAction.done => context.t.actions.taskHub.actions.done,
        TaskHubQuickAction.reopen => context.t.actions.taskHub.actions.reopen,
        TaskHubQuickAction.redo => context.t.actions.taskHub.actions.redo,
        TaskHubQuickAction.dismiss => context.t.common.actions.delete,
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
    final snackToken = Object();
    _quickActionSnackToken = snackToken;
    _quickActionSnackMessenger = messenger;
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
    if (snackController == null) {
      if (identical(_quickActionSnackToken, snackToken)) {
        _quickActionSnackToken = null;
        _quickActionSnackMessenger = null;
      }
      return;
    }
    final shouldForceAutoDismiss =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    Timer? autoDismissTimer;
    if (shouldForceAutoDismiss) {
      autoDismissTimer = Timer(
        const Duration(seconds: 3),
        snackController.close,
      );
      _quickActionSnackAutoDismissTimer = autoDismissTimer;
      _quickActionSnackMessenger = messenger;
    }

    unawaited(
      snackController.closed.then((_) {
        autoDismissTimer?.cancel();
        if (autoDismissTimer != null &&
            identical(_quickActionSnackAutoDismissTimer, autoDismissTimer)) {
          _quickActionSnackAutoDismissTimer = null;
        }
        if (identical(_quickActionSnackToken, snackToken)) {
          _quickActionSnackToken = null;
          _quickActionSnackMessenger = null;
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
              final scheduled = <Todo>[
                ...summary.dueTodos,
                ...summary.upcomingTodos,
              ];
              final doneVisibleCount = math.min(
                _doneVisibleCount,
                summary.doneTodos.length,
              );
              final doneVisibleTodos = summary.doneTodos
                  .take(doneVisibleCount)
                  .toList(growable: false);
              final hasMoreDone = doneVisibleCount < summary.doneTodos.length;
              final hasTodos = scheduled.isNotEmpty ||
                  summary.dueReviewTodos.isNotEmpty ||
                  summary.unscheduledTodos.isNotEmpty ||
                  summary.doneTodos.isNotEmpty;
              if (!hasTodos) {
                return Center(child: Text(context.t.actions.agenda.empty));
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TaskHubPageSection(
                    key: const ValueKey('task_hub_page_section_scheduled'),
                    title: context.t.actions.taskHub.scheduledSection,
                    todos: scheduled,
                    sectionKind: TaskHubPageSectionKind.scheduled,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                  ),
                  TaskHubPageMergedUnscheduledSection(
                    key: const ValueKey(
                      'task_hub_page_section_unscheduled_merged',
                    ),
                    dueReviewTodos: summary.dueReviewTodos,
                    unscheduledTodos: summary.unscheduledTodos,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                  ),
                  TaskHubPageSection(
                    key: const ValueKey('task_hub_page_section_done'),
                    title: context.t.actions.todoStatus.done,
                    todos: doneVisibleTodos,
                    totalCount: summary.doneTodos.length,
                    sectionKind: TaskHubPageSectionKind.done,
                    onQuickAction: _applyQuickAction,
                    onOpenTodo: _openTodoDetail,
                    footer: hasMoreDone
                        ? TaskHubPageDoneLoadMoreButton(
                            onPressed: () =>
                                _loadMoreDone(summary.doneTodos.length),
                          )
                        : null,
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
