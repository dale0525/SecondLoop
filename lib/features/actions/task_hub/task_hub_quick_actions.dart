import 'dart:typed_data';

import '../../../core/ai/todo_followup_task_classifier.dart';
import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import '../settings/actions_settings_store.dart';
import 'task_priority_models.dart';

enum TaskHubQuickAction {
  today,
  tomorrow,
  start,
  moveUpABit,
  moveDownABit,
  restoreAiOrder,
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
  final TaskHubUndoManualNudgeSnapshot? previousManualSignal;
  final String? createdTodoId;
  final bool shouldNotifySync;
}

class TaskHubQuickActionsController {
  TaskHubQuickActionsController({
    required this.backend,
    required this.sessionKey,
    this.confirmDoneWithIncompleteChecklist,
    this.checklistProgressByTodoId = const <String, TodoChecklistProgress>{},
    DateTime Function()? nowLocal,
  }) : _nowLocalOverride = nowLocal;

  final AppBackend backend;
  final Uint8List sessionKey;
  final ConfirmDoneWithIncompleteChecklist? confirmDoneWithIncompleteChecklist;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;
  DateTime Function() get _nowLocal => _nowLocalOverride ?? DateTime.now;
  final DateTime Function()? _nowLocalOverride;

  Future<bool> hasIncompleteChecklist(Todo todo) async {
    final progress = checklistProgressByTodoId[todo.id];
    if (progress != null && progress.totalCount > 0) {
      if (progress.doneCount < progress.totalCount) {
        return true;
      }
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
    final nowLocal = _nowLocal();
    final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;
    final settings = switch (action) {
      TaskHubQuickAction.today ||
      TaskHubQuickAction.tomorrow ||
      TaskHubQuickAction.reopen ||
      TaskHubQuickAction.redo =>
        await _loadActionsSettingsWithFallback(),
      _ => null,
    };

    switch (action) {
      case TaskHubQuickAction.today:
        return _applyScheduleChange(
          todo,
          action: action,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings!,
          offsetDays: 0,
        );
      case TaskHubQuickAction.tomorrow:
        return _applyScheduleChange(
          todo,
          action: action,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings!,
          offsetDays: 1,
        );
      case TaskHubQuickAction.start:
        return _applyStart(todo);
      case TaskHubQuickAction.moveUpABit:
        return _applyDirectionalMove(todo, action: action, direction: 1);
      case TaskHubQuickAction.moveDownABit:
        return _applyDirectionalMove(todo, action: action, direction: -1);
      case TaskHubQuickAction.restoreAiOrder:
        return _applyRestoreAiOrder(todo, action: action);
      case TaskHubQuickAction.increaseUrgency:
        return _applySignalChange(
          todo,
          action: action,
          urgencyDelta: 1,
        );
      case TaskHubQuickAction.decreaseUrgency:
        return _applySignalChange(
          todo,
          action: action,
          urgencyDelta: -1,
        );
      case TaskHubQuickAction.increaseImportance:
        return _applySignalChange(
          todo,
          action: action,
          importanceDelta: 1,
        );
      case TaskHubQuickAction.decreaseImportance:
        return _applySignalChange(
          todo,
          action: action,
          importanceDelta: -1,
        );
      case TaskHubQuickAction.done:
        return _applyDone(todo);
      case TaskHubQuickAction.reopen:
        return _applyReopen(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings!,
        );
      case TaskHubQuickAction.redo:
        return _applyRedo(
          todo,
          nowLocal: nowLocal,
          nowUtcMs: nowUtcMs,
          settings: settings!,
        );
      case TaskHubQuickAction.dismiss:
        return _applyDismiss(todo);
    }
  }

  Future<ActionsSettings> _loadActionsSettingsWithFallback() async {
    try {
      return await ActionsSettingsStore.load();
    } catch (_) {
      return ActionsSettingsStore.defaultSettings;
    }
  }

  Future<TaskHubUndoTicket?> _applySignalChange(
    Todo todo, {
    required TaskHubQuickAction action,
    int importanceDelta = 0,
    int urgencyDelta = 0,
  }) async {
    final previousManualSignal = _manualSignalFromTodo(todo);
    final currentImportance = normalizeTaskPriorityManualImportanceScore(
      todo.manualImportanceNudgeScore ?? 0,
      todo.manualUrgencyNudgeScore ?? 0,
    );
    final currentUrgency = normalizeTaskPriorityManualUrgencyScore(
      todo.manualImportanceNudgeScore ?? 0,
      todo.manualUrgencyNudgeScore ?? 0,
    );
    final clearsUserMoveEncoding = hasTaskPriorityUserMoveEncoding(
      todo.manualImportanceNudgeScore ?? 0,
      todo.manualUrgencyNudgeScore ?? 0,
    );
    final nextImportance = switch (importanceDelta) {
      > 0 => 1,
      < 0 => -1,
      _ => currentImportance,
    };
    final nextUrgency = switch (urgencyDelta) {
      > 0 => 1,
      < 0 => -1,
      _ => currentUrgency,
    };
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      manualImportanceNudgeScore: importanceDelta != 0
          ? nextImportance
          : (clearsUserMoveEncoding ? currentImportance : null),
      manualUrgencyNudgeScore: urgencyDelta != 0
          ? nextUrgency
          : (clearsUserMoveEncoding ? currentUrgency : null),
    );
    if ((updated.manualImportanceNudgeScore ?? 0) ==
            (todo.manualImportanceNudgeScore ?? 0) &&
        (updated.manualUrgencyNudgeScore ?? 0) ==
            (todo.manualUrgencyNudgeScore ?? 0)) {
      return null;
    }
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: action,
      previousManualSignal: previousManualSignal,
    );
  }

  Future<TaskHubUndoTicket?> _applyDirectionalMove(
    Todo todo, {
    required TaskHubQuickAction action,
    required int direction,
  }) async {
    assert(direction == 1 || direction == -1);
    final currentUrgency = todo.manualUrgencyNudgeScore ?? 0;
    final currentImportance = todo.manualImportanceNudgeScore ?? 0;
    final desiredMarker = direction * taskPriorityUserMoveEncodedMarker;
    if (currentUrgency == desiredMarker && currentImportance == desiredMarker) {
      return null;
    }
    final previousManualSignal = _manualSignalFromTodo(todo);
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      manualUrgencyNudgeScore: desiredMarker,
      manualImportanceNudgeScore: desiredMarker,
    );
    if ((updated.manualImportanceNudgeScore ?? 0) == currentImportance &&
        (updated.manualUrgencyNudgeScore ?? 0) == currentUrgency) {
      return null;
    }
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: action,
      previousManualSignal: previousManualSignal,
    );
  }

  Future<TaskHubUndoTicket?> _applyRestoreAiOrder(
    Todo todo, {
    required TaskHubQuickAction action,
  }) async {
    final currentUrgency = todo.manualUrgencyNudgeScore ?? 0;
    final currentImportance = todo.manualImportanceNudgeScore ?? 0;
    if (currentUrgency == 0 && currentImportance == 0) {
      return null;
    }
    final previousManualSignal = _manualSignalFromTodo(todo);
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      clearManualImportanceNudgeScore: true,
      clearManualUrgencyNudgeScore: true,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: action,
      previousManualSignal: previousManualSignal,
    );
  }

  Future<TaskHubUndoTicket> _applyStart(Todo todo) async {
    final previousManualSignal = _manualSignalFromTodo(todo);
    final shouldClearReviewScheduling = todo.status == 'inbox';
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: 'in_progress',
      reviewStage: shouldClearReviewScheduling ? null : todo.reviewStage,
      clearReviewStage: shouldClearReviewScheduling || todo.reviewStage == null,
      nextReviewAtMs: shouldClearReviewScheduling ? null : todo.nextReviewAtMs,
      clearNextReviewAtMs:
          shouldClearReviewScheduling || todo.nextReviewAtMs == null,
      clearManualImportanceNudgeScore: true,
      clearManualUrgencyNudgeScore: true,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.start,
      previousManualSignal: previousManualSignal,
    );
  }

  Future<TaskHubUndoTicket?> _applyScheduleChange(
    Todo todo, {
    required TaskHubQuickAction action,
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
    required int offsetDays,
  }) async {
    final dueLocal = offsetDays == 0
        ? _todayDueLocal(nowLocal, settings)
        : _scheduledMorningLocal(nowLocal, settings, offsetDays: offsetDays);
    if (_isScheduleNoOp(todo.dueAtMs, dueLocal, nowLocal: nowLocal)) {
      return null;
    }
    final previousManualSignal = _manualSignalFromTodo(todo);
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: todo.status == 'in_progress' ? 'in_progress' : 'open',
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      clearReviewStage: true,
      clearNextReviewAtMs: true,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: action,
      previousManualSignal: previousManualSignal,
    );
  }

  DateTime _todayDueLocal(DateTime nowLocal, ActionsSettings settings) {
    final todayDayEnd = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      settings.dayEndTime.hour,
      settings.dayEndTime.minute,
    );
    if (todayDayEnd.isAfter(nowLocal)) {
      return todayDayEnd;
    }
    return _tomorrowMorningLocal(nowLocal, settings);
  }

  DateTime _scheduledMorningLocal(
    DateTime nowLocal,
    ActionsSettings settings, {
    required int offsetDays,
  }) {
    final targetDay = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(Duration(days: offsetDays));
    return DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      settings.morningTime.hour,
      settings.morningTime.minute,
    );
  }

  DateTime _tomorrowMorningLocal(DateTime nowLocal, ActionsSettings settings) {
    final tomorrow = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      settings.morningTime.hour,
      settings.morningTime.minute,
    );
  }

  Future<TaskHubUndoTicket?> _applyDone(Todo todo) async {
    final hasIncomplete = await hasIncompleteChecklist(todo);
    if (hasIncomplete && confirmDoneWithIncompleteChecklist != null) {
      final confirmed = await confirmDoneWithIncompleteChecklist!.call(todo);
      if (!confirmed) return null;
    }
    final previousManualSignal = _manualSignalFromTodo(todo);
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: 'done',
      clearManualImportanceNudgeScore: true,
      clearManualUrgencyNudgeScore: true,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.done,
      previousManualSignal: previousManualSignal,
    );
  }

  Future<TaskHubUndoTicket> _applyReopen(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) async {
    final previousManualSignal = _manualSignalFromTodo(todo);
    final dueLocal = _reopenDueLocal(nowLocal, settings);
    // Reopen intentionally re-activates the task as in-progress so it surfaces
    // in the active focus flow immediately instead of returning to backlog.
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: 'in_progress',
      dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
      clearReviewStage: true,
      clearNextReviewAtMs: true,
      lastReviewAtMs: nowUtcMs,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.reopen,
      previousManualSignal: previousManualSignal,
    );
  }

  DateTime _reopenDueLocal(DateTime nowLocal, ActionsSettings settings) {
    return _todayDueLocal(nowLocal, settings);
  }

  Future<TaskHubUndoTicket> _applyRedo(
    Todo todo, {
    required DateTime nowLocal,
    required int nowUtcMs,
    required ActionsSettings settings,
  }) async {
    final previousManualSignal = _manualSignalFromTodo(todo);
    final dueLocal = _todayDueLocal(nowLocal, settings);
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
      manualImportanceNudgeScore: previousManualSignal?.importanceScore,
      manualUrgencyNudgeScore: previousManualSignal?.urgencyScore,
    );
    if (backend.supportsTodoFollowupSuggestions) {
      final taskType = classifyTodoFollowupTaskType(todo.title);
      final taskTypeHint =
          taskType == TodoFollowupTaskType.unknown ? null : taskType.wireValue;
      await backend.enqueueTodoFollowupGenerationJob(
        sessionKey,
        todoId: createdTodoId,
        triggerKind: 'auto_create',
        taskTypeHint: taskTypeHint,
        nowMs: nowUtcMs,
      );
    }
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.redo,
      previousManualSignal: previousManualSignal,
      createdTodoId: createdTodoId,
    );
  }

  Future<TaskHubUndoTicket> _applyDismiss(Todo todo) async {
    final previousManualSignal = _manualSignalFromTodo(todo);
    final updated = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: 'dismissed',
      clearManualImportanceNudgeScore: true,
      clearManualUrgencyNudgeScore: true,
    );
    return TaskHubUndoTicket(
      todo: todo,
      updatedTodo: updated,
      action: TaskHubQuickAction.dismiss,
      previousManualSignal: previousManualSignal,
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

    final original = ticket.todo;
    final updated = ticket.updatedTodo;
    if (_canUndoWithTransition(original, updated)) {
      await backend.transitionTodo(
        sessionKey,
        todoId: original.id,
        newStatus: original.status != updated.status ? original.status : null,
        dueAtMs: original.dueAtMs,
        clearDueAtMs: original.dueAtMs == null,
        reviewStage: original.reviewStage,
        clearReviewStage: original.reviewStage == null,
        nextReviewAtMs: original.nextReviewAtMs,
        clearNextReviewAtMs: original.nextReviewAtMs == null,
        lastReviewAtMs: original.lastReviewAtMs,
        clearLastReviewAtMs: original.lastReviewAtMs == null,
        manualImportanceNudgeScore: original.manualImportanceNudgeScore,
        clearManualImportanceNudgeScore:
            (original.manualImportanceNudgeScore ?? 0) == 0,
        manualUrgencyNudgeScore: original.manualUrgencyNudgeScore,
        clearManualUrgencyNudgeScore:
            (original.manualUrgencyNudgeScore ?? 0) == 0,
      );
      return;
    }

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
      manualImportanceNudgeScore: original.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: original.manualUrgencyNudgeScore,
    );
  }

  TaskHubUndoManualNudgeSnapshot? _manualSignalFromTodo(Todo todo) {
    final importance = todo.manualImportanceNudgeScore ?? 0;
    final urgency = todo.manualUrgencyNudgeScore ?? 0;
    if (importance == 0 && urgency == 0) {
      return null;
    }
    return TaskHubUndoManualNudgeSnapshot(
      importanceScore: importance,
      urgencyScore: urgency,
    );
  }

  bool _isScheduleNoOp(
    int? existingDueAtMs,
    DateTime targetLocal, {
    required DateTime nowLocal,
  }) {
    if (existingDueAtMs == null) {
      return false;
    }
    final existingLocal =
        DateTime.fromMillisecondsSinceEpoch(existingDueAtMs, isUtc: true)
            .toLocal();
    final isSameLocalDate = existingLocal.year == targetLocal.year &&
        existingLocal.month == targetLocal.month &&
        existingLocal.day == targetLocal.day;
    if (!isSameLocalDate) {
      return false;
    }

    final targetDayStart = DateTime(
      targetLocal.year,
      targetLocal.month,
      targetLocal.day,
    );
    final existingDayStart = DateTime(
      existingLocal.year,
      existingLocal.month,
      existingLocal.day,
    );
    final tomorrowStart = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(const Duration(days: 1));
    final isTomorrowBucket =
        existingDayStart == tomorrowStart && targetDayStart == tomorrowStart;
    if (isTomorrowBucket) {
      return true;
    }

    return existingLocal == targetLocal;
  }

  bool _canUndoWithTransition(Todo original, Todo updated) {
    return original.id == updated.id &&
        original.title == updated.title &&
        original.sourceEntryId == updated.sourceEntryId;
  }
}

class TaskHubUndoManualNudgeSnapshot {
  const TaskHubUndoManualNudgeSnapshot({
    required this.importanceScore,
    required this.urgencyScore,
  });

  final int importanceScore;
  final int urgencyScore;
}
