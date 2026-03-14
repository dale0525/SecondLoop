import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';

enum TaskHubQuickAction {
  today,
  tonight,
  tomorrow,
  pauseTomorrow,
  thisWeek,
  later,
  start,
  moveToInbox,
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
    this.createdTodoId,
  });

  final Todo todo;
  final Todo updatedTodo;
  final TaskHubQuickAction action;
  final String? createdTodoId;
}

class TaskHubQuickActionsController {
  const TaskHubQuickActionsController({
    required this.backend,
    required this.sessionKey,
    this.confirmDoneWithIncompleteChecklist,
  });

  final AppBackend backend;
  final Uint8List sessionKey;
  final ConfirmDoneWithIncompleteChecklist? confirmDoneWithIncompleteChecklist;

  Future<bool> hasIncompleteChecklist(Todo todo) async {
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
      case TaskHubQuickAction.today:
      case TaskHubQuickAction.tonight:
        {
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
            status: 'open',
            sourceEntryId: todo.sourceEntryId,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: nowUtcMs,
          );
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.tomorrow:
      case TaskHubQuickAction.pauseTomorrow:
        {
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
          final updated = await backend.upsertTodo(
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
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.thisWeek:
        {
          final dueLocal = _nextWeekdayAtDayEnd(
            nowLocal,
            settings.weeklyReviewWeekday,
            settings.dayEndTime,
          );
          final updated = await backend.upsertTodo(
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
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.later:
        {
          final nextLocal =
              ReviewBackoff.initialNextReviewAt(nowLocal, settings);
          final updated = await backend.upsertTodo(
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
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.start:
        {
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'in_progress',
          );
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.moveToInbox:
        {
          final nextLocal =
              ReviewBackoff.initialNextReviewAt(nowLocal, settings);
          final updated = await backend.upsertTodo(
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
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
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
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'done',
          );
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.reopen:
        {
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'open',
          );
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
      case TaskHubQuickAction.redo:
        {
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
            action: action,
            createdTodoId: createdTodoId,
          );
        }
      case TaskHubQuickAction.dismiss:
        {
          final updated = await backend.setTodoStatus(
            sessionKey,
            todoId: todo.id,
            newStatus: 'dismissed',
          );
          return TaskHubUndoTicket(
            todo: todo,
            updatedTodo: updated,
            action: action,
          );
        }
    }
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

DateTime _nextWeekdayAtDayEnd(
  DateTime nowLocal,
  int weekday,
  TimeOfDay dayEndTime,
) {
  final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final normalizedWeekday = weekday.clamp(DateTime.monday, DateTime.sunday);
  final deltaDays = (normalizedWeekday - base.weekday) % 7;
  final candidateDay = base.add(Duration(days: deltaDays));
  final candidate = DateTime(
    candidateDay.year,
    candidateDay.month,
    candidateDay.day,
    dayEndTime.hour,
    dayEndTime.minute,
  );
  if (candidate.isAfter(nowLocal)) {
    return candidate;
  }
  return candidate.add(const Duration(days: 7));
}
