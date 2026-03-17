import 'dart:typed_data';

import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';
import 'task_priority_signal_store.dart';

enum TaskHubQuickAction {
  today,
  tomorrow,
  start,
  increaseUrgency,
  decreaseUrgency,
  increaseImportance,
  decreaseImportance,
  done,
  reopen,
  redo,
  dismiss,
}

typedef ConfirmDoneWithIncompleteChecklist = Future<bool> Function(Todo todo);

class TaskHubUndoTicket {
  const TaskHubUndoTicket({
    required this.todo,
    required this.updatedTodo,
    required this.action,
    this.previousManualSignal,
    this.createdTodoId,
    this.shouldNotifySync = true,
  });

  final Todo todo;
  final Todo updatedTodo;
  final TaskHubQuickAction action;
  final TaskPriorityManualSignal? previousManualSignal;
  final String? createdTodoId;
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
    final nowLocal = DateTime.now();
    final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;

    switch (action) {
      case TaskHubQuickAction.today:
        final settings = await ActionsSettingsStore.load();
        return _applyScheduleChange(
          todo,
          action: action,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          offsetDays: 0,
        );
      case TaskHubQuickAction.tomorrow:
        final settings = await ActionsSettingsStore.load();
        return _applyScheduleChange(
          todo,
          action: action,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          offsetDays: 1,
        );
      case TaskHubQuickAction.start:
        return _applyStart(todo, nowUtcMs: nowUtcMs);
      case TaskHubQuickAction.increaseUrgency:
        final settings = await ActionsSettingsStore.load();
        return _applyUrgencyChange(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          increase: true,
        );
      case TaskHubQuickAction.decreaseUrgency:
        final settings = await ActionsSettingsStore.load();
        return _applyUrgencyChange(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
          increase: false,
        );
      case TaskHubQuickAction.increaseImportance:
        final previous = await signalStore.readForTodo(todo.id);
        await signalStore.adjustImportance(todo.id, increase: true);
        return TaskHubUndoTicket(
          todo: todo,
          updatedTodo: todo,
          action: action,
          previousManualSignal: previous,
          shouldNotifySync: false,
        );
      case TaskHubQuickAction.decreaseImportance:
        final previous = await signalStore.readForTodo(todo.id);
        await signalStore.adjustImportance(todo.id, increase: false);
        return TaskHubUndoTicket(
          todo: todo,
          updatedTodo: todo,
          action: action,
          previousManualSignal: previous,
          shouldNotifySync: false,
        );
      case TaskHubQuickAction.done:
        return _applyDone(todo);
      case TaskHubQuickAction.reopen:
        final settings = await ActionsSettingsStore.load();
        return _applyReopen(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
        );
      case TaskHubQuickAction.redo:
        final settings = await ActionsSettingsStore.load();
        return _applyRedo(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings,
        );
      case TaskHubQuickAction.dismiss:
        return _applyDismiss(todo);
    }
  }

  Future<TaskHubUndoTicket> _applyStart(
    Todo todo, {
    required int nowUtcMs,
  }) async {
    final previousSignal = await signalStore.readForTodo(todo.id);
    final clearedSignal = await _clearPreferredStatusIfNeeded(
      todo.id,
      previousSignal: previousSignal,
    );
    final updated = await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: todo.dueAtMs,
      status: 'in_progress',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.start,
      previousManualSignal: clearedSignal,
    );
  }

  Future<TaskHubUndoTicket> _applyScheduleChange(
    Todo todo, {
    required TaskHubQuickAction action,
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
    required int offsetDays,
  }) async {
    final previousSignal = await signalStore.readForTodo(todo.id);
    final clearedSignal = await _clearPreferredStatusIfNeeded(
      todo.id,
      previousSignal: previousSignal,
    );
    final targetDay = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(Duration(days: offsetDays));
    final dueLocal = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );
    final updated = await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: todo.status == 'in_progress' ? 'in_progress' : 'open',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: action,
      previousManualSignal: clearedSignal,
    );
  }

  Future<TaskHubUndoTicket?> _applyDone(Todo todo) async {
    final hasIncomplete = await hasIncompleteChecklist(todo);
    if (hasIncomplete && confirmDoneWithIncompleteChecklist != null) {
      final confirmed = await confirmDoneWithIncompleteChecklist!.call(todo);
      if (!confirmed) return null;
    }
    final previousSignal = await signalStore.readForTodo(todo.id);
    final updated = await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: 'done',
    );
    final clearedSignal = await _clearPreferredStatusIfNeeded(
      todo.id,
      previousSignal: previousSignal,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.done,
      previousManualSignal: clearedSignal,
    );
  }

  Future<TaskHubUndoTicket> _applyReopen(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) async {
    final previousSignal = await signalStore.readForTodo(todo.id);
    final clearedSignal = await _clearPreferredStatusIfNeeded(
      todo.id,
      previousSignal: previousSignal,
    );
    final dueLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );
    final updated = await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: 'in_progress',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.reopen,
      previousManualSignal: clearedSignal,
    );
  }

  Future<TaskHubUndoTicket> _applyRedo(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) async {
    final dueLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );
    final createdTodoId =
        'todo:task_hub_redo:${todo.id}:${nowLocal.toUtc().microsecondsSinceEpoch}';
    final updated = await backend.upsertTodo(
      sessionKey,
      id: createdTodoId,
      title: todo.title,
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      status: 'open',
      sourceEntryId: todo.sourceEntryId,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.redo,
      createdTodoId: createdTodoId,
    );
  }

  Future<TaskHubUndoTicket> _applyDismiss(Todo todo) async {
    final updated = await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: 'dismissed',
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.dismiss,
    );
  }

  Future<TaskPriorityManualSignal?> _clearPreferredStatusIfNeeded(
    String todoId, {
    TaskPriorityManualSignal? previousSignal,
  }) async {
    if (previousSignal?.preferredStatus == null) {
      return null;
    }
    try {
      await signalStore.clearPreferredStatusForTodo(todoId);
      return previousSignal;
    } catch (_) {
      return null;
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
    final bucket = _effectiveUrgencyBucketFor(
      todo,
      nowLocal: nowLocal,
      signal: currentSignal,
    );
    final isReviewQueueTodo =
        todo.reviewStage != null && todo.nextReviewAtMs != null;
    final targetBucket = switch ((bucket, increase)) {
      (_TaskUrgencyBucket.backlog, true) => _TaskUrgencyBucket.scheduled,
      (_TaskUrgencyBucket.scheduled, true) => _TaskUrgencyBucket.urgent,
      (_TaskUrgencyBucket.urgent, true) => _TaskUrgencyBucket.urgent,
      (_TaskUrgencyBucket.urgent, false) when isReviewQueueTodo =>
        _TaskUrgencyBucket.backlog,
      (_TaskUrgencyBucket.urgent, false) => _TaskUrgencyBucket.scheduled,
      (_TaskUrgencyBucket.scheduled, false) => _TaskUrgencyBucket.backlog,
      (_TaskUrgencyBucket.backlog, false) => _TaskUrgencyBucket.backlog,
    };

    if (bucket == _TaskUrgencyBucket.backlog && !increase) {
      await signalStore.setForTodo(
        todo.id,
        currentSignal.copyWith(
          isUrgent: false,
          clearPreferredStatus: currentSignal.preferredStatus != null,
        ),
      );
      return TaskHubUndoTicket(
        todo: todo,
        updatedTodo: todo,
        action: TaskHubQuickAction.decreaseUrgency,
        previousManualSignal: previousSignal,
        shouldNotifySync: false,
      );
    }

    if (targetBucket == _TaskUrgencyBucket.urgent && bucket == targetBucket) {
      await signalStore.setForTodo(
        todo.id,
        currentSignal.copyWith(
          isUrgent: true,
          clearPreferredStatus: true,
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

    final shouldPersistInProgressPreference =
        !increase && todo.status == 'in_progress';
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
            shouldPersistInProgressPreference ? 'in_progress' : null,
        clearPreferredStatus:
            !shouldPersistInProgressPreference || shouldRestoreInProgress,
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
    if (ticket.action == TaskHubQuickAction.redo &&
        ticket.createdTodoId != null) {
      await backend.deleteTodo(
        sessionKey,
        todoId: ticket.createdTodoId!,
      );
      return;
    }

    if (ticket.previousManualSignal != null) {
      await signalStore.restoreForTodo(
        ticket.todo.id,
        ticket.previousManualSignal,
      );
    } else if (ticket.action == TaskHubQuickAction.increaseImportance ||
        ticket.action == TaskHubQuickAction.decreaseImportance ||
        ticket.action == TaskHubQuickAction.increaseUrgency ||
        ticket.action == TaskHubQuickAction.decreaseUrgency) {
      await signalStore.restoreForTodo(
        ticket.todo.id,
        ticket.previousManualSignal,
      );
      if (!ticket.shouldNotifySync &&
          ticket.updatedTodo.id == ticket.todo.id &&
          ticket.updatedTodo == ticket.todo) {
        return;
      }
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

_TaskUrgencyBucket _effectiveUrgencyBucketFor(
  Todo todo, {
  required DateTime nowLocal,
  required TaskPriorityManualSignal signal,
}) {
  final bucket = _urgencyBucketFor(todo, nowLocal: nowLocal);
  if (_hasHardUrgencyGuard(todo, nowLocal: nowLocal)) {
    return bucket;
  }

  final manualUrgency = signal.isUrgent;
  if (manualUrgency == null) {
    return bucket;
  }
  if (manualUrgency) {
    return _TaskUrgencyBucket.urgent;
  }
  return switch (bucket) {
    _TaskUrgencyBucket.scheduled => _TaskUrgencyBucket.scheduled,
    _TaskUrgencyBucket.urgent => _TaskUrgencyBucket.backlog,
    _TaskUrgencyBucket.backlog => _TaskUrgencyBucket.backlog,
  };
}

bool _hasHardUrgencyGuard(
  Todo todo, {
  required DateTime nowLocal,
}) {
  if (todo.status == 'in_progress') return true;
  final dueAtMs = todo.dueAtMs;
  if (dueAtMs == null) return false;
  final dueLocal =
      DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
  return dueLocal.isBefore(nowLocal) ||
      (dueLocal.year == nowLocal.year &&
          dueLocal.month == nowLocal.month &&
          dueLocal.day == nowLocal.day);
}
