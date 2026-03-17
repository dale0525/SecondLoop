import 'dart:typed_data';

import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';
import 'task_priority_signal_store.dart';

enum TaskHubQuickAction {
  increaseUrgency,
  decreaseUrgency,
  increaseImportance,
  decreaseImportance,
  done,
  reopen,
}

typedef ConfirmDoneWithIncompleteChecklist = Future<bool> Function(Todo todo);

class TaskHubUndoTicket {
  const TaskHubUndoTicket({
    required this.todo,
    required this.updatedTodo,
    required this.action,
    this.previousManualSignal,
    this.shouldNotifySync = true,
  });

  final Todo todo;
  final Todo updatedTodo;
  final TaskHubQuickAction action;
  final TaskPriorityManualSignal? previousManualSignal;
  final bool shouldNotifySync;
}

class TaskHubQuickActionsController {
  const TaskHubQuickActionsController({
    required this.backend,
    required this.sessionKey,
    this.signalStore = const TaskPrioritySignalStore(),
    this.confirmDoneWithIncompleteChecklist,
    this.checklistProgressByTodoId = const <String, TodoChecklistProgress>{},
  });

  final AppBackend backend;
  final Uint8List sessionKey;
  final TaskPrioritySignalStore signalStore;
  final ConfirmDoneWithIncompleteChecklist? confirmDoneWithIncompleteChecklist;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;

  Future<bool> hasIncompleteChecklist(Todo todo) async {
    final progress = checklistProgressByTodoId[todo.id];
    if (progress == null || progress.totalCount == 0) {
      return false;
    }
    if (progress.doneCount >= progress.totalCount) {
      return false;
    }
    try {
      final items = await backend.listTodoChecklistItems(sessionKey, todo.id);
      return items.any((item) => !item.isDone);
    } catch (_) {
      return false;
    }
  }

  Future<TaskHubUndoTicket?> apply(
    Todo todo,
    TaskHubQuickAction action,
  ) async {
    final settings = await ActionsSettingsStore.load();
    final nowLocal = DateTime.now();
    final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;

    switch (action) {
      case TaskHubQuickAction.increaseUrgency:
        return _applyUrgencyChange(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          increase: true,
        );
      case TaskHubQuickAction.decreaseUrgency:
        return _applyUrgencyChange(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          increase: false,
        );
      case TaskHubQuickAction.increaseImportance:
        {
          final previous = await signalStore.readForTodo(todo.id);
          await signalStore.adjustImportance(todo.id, increase: true);
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: todo,
            action: action,
            previousManualSignal: previous,
            shouldNotifySync: false,
          );
        }
      case TaskHubQuickAction.decreaseImportance:
        {
          final previous = await signalStore.readForTodo(todo.id);
          await signalStore.adjustImportance(todo.id, increase: false);
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: todo,
            action: action,
            previousManualSignal: previous,
            shouldNotifySync: false,
          );
        }
      case TaskHubQuickAction.done:
        {
          final hasIncomplete = await hasIncompleteChecklist(todo);
          if (hasIncomplete && confirmDoneWithIncompleteChecklist != null) {
            final confirmed =
                await confirmDoneWithIncompleteChecklist!.call(todo);
            if (!confirmed) return null;
          }
          final previousSignal = await signalStore.readForTodo(todo.id);
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'done',
          );
          TaskPriorityManualSignal? clearedSignal;
          if (previousSignal?.preferredStatus != null) {
            try {
              await signalStore.clearPreferredStatusForTodo(todo.id);
              clearedSignal = previousSignal;
            } catch (_) {
              clearedSignal = null;
            }
          }
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
            previousManualSignal: clearedSignal,
          );
        }
      case TaskHubQuickAction.reopen:
        {
          final previousSignal = await signalStore.readForTodo(todo.id);
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'open',
          );
          TaskPriorityManualSignal? clearedSignal;
          if (previousSignal?.preferredStatus != null) {
            try {
              await signalStore.clearPreferredStatusForTodo(todo.id);
              clearedSignal = previousSignal;
            } catch (_) {
              clearedSignal = null;
            }
          }
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
            previousManualSignal: clearedSignal,
          );
        }
    }
  }

  Future<TaskHubUndoTicket> _applyUrgencyChange(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
    required bool increase,
  }) async {
    final previousSignal = await signalStore.readForTodo(todo.id);
    final currentSignal = previousSignal ?? const TaskPriorityManualSignal();
    final bucket = _urgencyBucketFor(todo, nowLocal: nowLocal);
    final targetBucket = switch ((bucket, increase)) {
      (_TaskUrgencyBucket.backlog, true) => _TaskUrgencyBucket.scheduled,
      (_TaskUrgencyBucket.scheduled, true) => _TaskUrgencyBucket.urgent,
      (_TaskUrgencyBucket.urgent, true) => _TaskUrgencyBucket.urgent,
      (_TaskUrgencyBucket.urgent, false) => _TaskUrgencyBucket.scheduled,
      (_TaskUrgencyBucket.scheduled, false) => _TaskUrgencyBucket.backlog,
      (_TaskUrgencyBucket.backlog, false) => _TaskUrgencyBucket.backlog,
    };

    if (bucket == _TaskUrgencyBucket.backlog && !increase) {
      await signalStore.setForTodo(
        todo.id,
        currentSignal.copyWith(isUrgent: false),
      );
      return TaskHubUndoTicket(
        todo: todo,
        updatedTodo: todo,
        action: increase
            ? TaskHubQuickAction.increaseUrgency
            : TaskHubQuickAction.decreaseUrgency,
        previousManualSignal: previousSignal,
        shouldNotifySync: false,
      );
    }

    if (targetBucket == _TaskUrgencyBucket.urgent && bucket == targetBucket) {
      await signalStore.setForTodo(
        todo.id,
        currentSignal.copyWith(
          isUrgent: true,
          clearPreferredStatus: todo.status == 'in_progress',
        ),
      );
      return TaskHubUndoTicket(
        todo: todo,
        updatedTodo: todo,
        action: increase
            ? TaskHubQuickAction.increaseUrgency
            : TaskHubQuickAction.decreaseUrgency,
        previousManualSignal: previousSignal,
        shouldNotifySync: false,
      );
    }

    final shouldRestoreInProgress = increase &&
        targetBucket == _TaskUrgencyBucket.urgent &&
        currentSignal.preferredStatus == 'in_progress';

    final updated = await switch (targetBucket) {
      _TaskUrgencyBucket.urgent when shouldRestoreInProgress =>
        _moveTodoToInProgress(
          todo,
          nowUtcMs: nowUtcMs,
        ),
      _TaskUrgencyBucket.urgent => _moveTodoToToday(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
        ),
      _TaskUrgencyBucket.scheduled => _moveTodoToTomorrow(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
        ),
      _TaskUrgencyBucket.backlog => _moveTodoToBacklog(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
        ),
    };
    await signalStore.setForTodo(
      todo.id,
      currentSignal.copyWith(
        isUrgent: increase
            ? (targetBucket == _TaskUrgencyBucket.urgent ? true : null)
            : false,
        clearUrgent: increase && targetBucket != _TaskUrgencyBucket.urgent,
        preferredStatus:
            !increase && todo.status == 'in_progress' ? 'in_progress' : null,
        clearPreferredStatus: shouldRestoreInProgress,
      ),
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: increase
          ? TaskHubQuickAction.increaseUrgency
          : TaskHubQuickAction.decreaseUrgency,
      previousManualSignal: previousSignal,
    );
  }

  Future<Todo> _moveTodoToInProgress(
    Todo todo, {
    required int nowUtcMs,
  }) {
    return backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: null,
      status: 'in_progress',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
  }

  Future<Todo> _moveTodoToToday(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) {
    final dueLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );
    return backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: 'open',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
  }

  Future<Todo> _moveTodoToTomorrow(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) {
    final tomorrow = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(const Duration(days: 1));
    final dueLocal = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      settings.morningTime.hour,
      settings.morningTime.minute,
    );
    return backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: 'open',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
  }

  Future<Todo> _moveTodoToBacklog(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) {
    final nextLocal = ReviewBackoff.initialNextReviewAt(nowLocal, settings);
    return backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: null,
      status: 'inbox',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: todo.reviewStage ?? 0,
      nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
      lastReviewAtMs: nowUtcMs,
    );
  }

  Future<void> undo(TaskHubUndoTicket ticket) async {
    switch (ticket.action) {
      case TaskHubQuickAction.increaseImportance:
      case TaskHubQuickAction.decreaseImportance:
      case TaskHubQuickAction.increaseUrgency:
      case TaskHubQuickAction.decreaseUrgency:
        await signalStore.restoreForTodo(
          ticket.todo.id,
          ticket.previousManualSignal,
        );
        if (!ticket.shouldNotifySync &&
            ticket.updatedTodo.id == ticket.todo.id &&
            ticket.updatedTodo == ticket.todo) {
          return;
        }
        break;
      case TaskHubQuickAction.done:
      case TaskHubQuickAction.reopen:
        if (ticket.previousManualSignal != null) {
          await signalStore.restoreForTodo(
            ticket.todo.id,
            ticket.previousManualSignal,
          );
        }
        break;
    }

    final original = ticket.todo;
    await backend.upsertTodo(
      sessionKey,
      id: original.id,
      title: original.title,
      dueAtMs: original.dueAtMs,
      status: original.status,
      sourceEntryId: original.sourceEntryId,
      reviewStage: original.reviewStage,
      nextReviewAtMs: original.nextReviewAtMs,
      lastReviewAtMs: original.lastReviewAtMs,
    );
  }
}

enum _TaskUrgencyBucket {
  backlog,
  scheduled,
  urgent,
}

_TaskUrgencyBucket _urgencyBucketFor(
  Todo todo, {
  required DateTime nowLocal,
}) {
  if (todo.status == 'done') return _TaskUrgencyBucket.backlog;
  if (todo.status == 'in_progress') return _TaskUrgencyBucket.urgent;
  final dueAtMs = todo.dueAtMs;
  if (dueAtMs != null) {
    final dueLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    if (dueLocal.isBefore(nowLocal) ||
        (dueLocal.year == nowLocal.year &&
            dueLocal.month == nowLocal.month &&
            dueLocal.day == nowLocal.day)) {
      return _TaskUrgencyBucket.urgent;
    }
    return _TaskUrgencyBucket.scheduled;
  }
  if (todo.reviewStage != null && todo.nextReviewAtMs != null) {
    final reviewLocal = DateTime.fromMillisecondsSinceEpoch(
      todo.nextReviewAtMs!,
      isUtc: true,
    ).toLocal();
    if (!reviewLocal.isAfter(nowLocal)) {
      return _TaskUrgencyBucket.urgent;
    }
  }
  return _TaskUrgencyBucket.backlog;
}
