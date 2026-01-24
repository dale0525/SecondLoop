import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import '../settings/actions_settings_store.dart';
import 'review_backoff.dart';

const _kTodoStatusDone = 'done';
const _kTodoStatusDismissed = 'dismissed';
const _kTodoStatusOpen = 'open';

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
      // Best-effort refresh of the page.
      setState(() {});
    }

    final pending = normalized
        .where((t) =>
            t.reviewStage != null &&
            t.nextReviewAtMs != null &&
            t.status != _kTodoStatusDone &&
            t.status != _kTodoStatusDismissed &&
            t.dueAtMs == null)
        .toList(growable: false);
    pending.sort((a, b) => a.nextReviewAtMs!.compareTo(b.nextReviewAtMs!));
    return pending;
  }

  Future<void> _refresh() async {
    setState(() => _todosFuture = _loadDueReviewTodos());
  }

  Future<void> _markDone(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: todo.dueAtMs,
      status: _kTodoStatusDone,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _dismiss(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: todo.dueAtMs,
      status: _kTodoStatusDismissed,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _snoozeToTomorrowMorning(Todo todo) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();
    final nextLocal =
        ReviewBackoff.initialNextReviewAt(DateTime.now(), settings);
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
