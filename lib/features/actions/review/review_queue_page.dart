import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_delete_confirm_dialog.dart';
import '../../../ui/sl_surface.dart';
import '../settings/actions_settings_store.dart';
import 'review_backoff.dart';

const _kTodoStatusDone = 'done';
const _kTodoStatusDismissed = 'dismissed';
const _kTodoStatusOpen = 'open';
const _kTodoStatusInProgress = 'in_progress';

class ReviewQueuePage extends StatefulWidget {
  const ReviewQueuePage({super.key});

  @override
  State<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends State<ReviewQueuePage> {
  Future<List<Todo>>? _todosFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _todosFuture ??= _loadDueReviewTodos();
  }

  Future<List<Todo>> _loadDueReviewTodos() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();

    final nowLocal = DateTime.now();
    final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;
    final todos = await backend.listTodos(sessionKey);

    var changed = false;
    final normalized = <Todo>[];
    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) {
        normalized.add(todo);
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
      if (rolled.stage != stage || rolled.nextReviewAtLocal != scheduledLocal) {
        changed = true;
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
        normalized.add(updated);
        continue;
      }

      normalized.add(todo);
    }

    if (changed && mounted) {
      _notifyLocalMutation();
      // Best-effort refresh of the page.
      setState(() {});
    }

    final pending = normalized
        .where((t) =>
            t.reviewStage != null &&
            t.nextReviewAtMs != null &&
            t.nextReviewAtMs! <= nowUtcMs &&
            t.status != _kTodoStatusDone &&
            t.status != _kTodoStatusDismissed &&
            t.dueAtMs == null)
        .toList(growable: false);
    pending.sort((a, b) => a.nextReviewAtMs!.compareTo(b.nextReviewAtMs!));
    return pending;
  }

  void _notifyLocalMutation() {
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _todosFuture = _loadDueReviewTodos();
    });
  }

  Future<void> _markDone(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: _kTodoStatusDone,
    );
    if (!mounted) return;
    _notifyLocalMutation();
    await _refresh();
  }

  Future<void> _markInProgress(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: _kTodoStatusInProgress,
    );
    if (!mounted) return;
    _notifyLocalMutation();
    await _refresh();
  }

  Future<void> _dismiss(Todo todo) async {
    final t = context.t;
    final confirmed = await showSlDeleteConfirmDialog(
      context,
      title: t.actions.todoDelete.dialog.title,
      message: t.actions.todoDelete.dialog.message,
      confirmLabel: t.actions.todoDelete.dialog.confirm,
      confirmButtonKey: ValueKey('review_queue_delete_confirm_${todo.id}'),
    );
    if (!mounted) return;
    if (!confirmed) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.deleteTodo(sessionKey, todoId: todo.id);
    if (!mounted) return;
    _notifyLocalMutation();
    await _refresh();
  }

  Future<void> _snoozeToTomorrowMorning(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();
    final nowLocal = DateTime.now();
    final nextLocal = ReviewBackoff.initialNextReviewAt(nowLocal, settings);
    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: todo.dueAtMs,
      status: todo.status,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: todo.reviewStage ?? 0,
      nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
      lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    final localizations = MaterialLocalizations.of(context);
    final scheduledText = '${localizations.formatShortDate(nextLocal)} '
        '${localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(nextLocal),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    )}';
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            context.t.actions.reviewQueue.snoozedUntil(when: scheduledText),
          ),
        ),
      );
    _notifyLocalMutation();
    await _refresh();
  }

  Future<void> _scheduleTodo(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();

    final now = DateTime.now();
    if (!mounted) return;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (pickedDate == null || !mounted) return;

    final dueLocal = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );

    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: _kTodoStatusOpen,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    _notifyLocalMutation();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.actions.reviewQueue.title),
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
                return Center(
                  child: Text(context.t.actions.reviewQueue.empty),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: todos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  return SlSurface(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todo.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SlButton(
                              icon: const Icon(Icons.calendar_today_rounded,
                                  size: 18),
                              onPressed: () => unawaited(_scheduleTodo(todo)),
                              child: Text(context
                                  .t.actions.reviewQueue.actions.schedule),
                            ),
                            SlButton(
                              variant: SlButtonVariant.outline,
                              icon: const Icon(Icons.snooze_rounded, size: 18),
                              onPressed: () =>
                                  unawaited(_snoozeToTomorrowMorning(todo)),
                              child: Text(
                                  context.t.actions.reviewQueue.actions.snooze),
                            ),
                            SlButton(
                              variant: SlButtonVariant.outline,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              onPressed: () => unawaited(_markDone(todo)),
                              child: Text(
                                  context.t.actions.reviewQueue.actions.done),
                            ),
                            SlButton(
                              variant: SlButtonVariant.outline,
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 18),
                              onPressed: () => unawaited(_markInProgress(todo)),
                              child: Text(
                                context.t.actions.reviewQueue.actions.start,
                              ),
                            ),
                            SlButton(
                              variant: SlButtonVariant.outline,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => unawaited(_dismiss(todo)),
                              child: Text(context
                                  .t.actions.reviewQueue.actions.dismiss),
                            ),
                          ],
                        ),
                      ],
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
