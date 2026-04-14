import 'dart:typed_data';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/src/rust/db.dart';

final class QuickActionBackendTestDouble extends AppBackend {
  QuickActionBackendTestDouble({
    List<Todo>? initialTodos,
    Map<String, List<TodoChecklistItem>>? checklistItemsByTodoId,
    this.failOnTransitionCall,
    this.ignoreClearManualNudges = false,
    this.enableFollowupSuggestions = false,
  })  : _checklistItemsByTodoId = Map<String, List<TodoChecklistItem>>.from(
          checklistItemsByTodoId ?? const <String, List<TodoChecklistItem>>{},
        ),
        _todosById = {
          for (final todo in initialTodos ?? const <Todo>[]) todo.id: todo,
        };

  final Map<String, Todo> _todosById;
  final Map<String, List<TodoChecklistItem>> _checklistItemsByTodoId;
  final int? failOnTransitionCall;
  final bool ignoreClearManualNudges;
  final bool enableFollowupSuggestions;
  var upsertTodoCalls = 0;
  var transitionTodoCalls = 0;
  var deleteTodoCalls = 0;
  var setTodoStatusCalls = 0;
  var enqueueTodoFollowupGenerationJobCalls = 0;
  int? lastTransitionManualImportanceNudgeScore;
  int? lastTransitionManualUrgencyNudgeScore;

  Todo current(String id) => _todosById[id]!;
  List<Todo> all() => _todosById.values.toList(growable: false);

  @override
  bool get supportsTodoFollowupSuggestions => enableFollowupSuggestions;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return _todosById.values.toList(growable: false);
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    upsertTodoCalls += 1;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todosById[id]?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ??
          _todosById[id]?.manualImportanceNudgeScore ??
          0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ??
          _todosById[id]?.manualUrgencyNudgeScore ??
          0,
    );
    _todosById[id] = updated;
    return updated;
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    transitionTodoCalls += 1;
    lastTransitionManualImportanceNudgeScore = manualImportanceNudgeScore;
    lastTransitionManualUrgencyNudgeScore = manualUrgencyNudgeScore;
    if (failOnTransitionCall == transitionTodoCalls) {
      throw StateError('transition failed');
    }
    final existing = _todosById[todoId]!;
    final targetStatus = newStatus ?? existing.status;
    final autoDueAtMs = existing.dueAtMs == null &&
            existing.status == 'open' &&
            (targetStatus == 'in_progress' || targetStatus == 'done')
        ? DateTime.now().toUtc().millisecondsSinceEpoch
        : existing.dueAtMs;
    final targetDueAtMs = clearDueAtMs ? null : (dueAtMs ?? autoDueAtMs);
    final targetReviewStage =
        clearReviewStage ? null : (reviewStage ?? existing.reviewStage);
    final targetNextReviewAtMs = clearNextReviewAtMs
        ? null
        : (nextReviewAtMs ?? existing.nextReviewAtMs);
    final targetLastReviewAtMs = clearLastReviewAtMs
        ? null
        : (lastReviewAtMs ?? existing.lastReviewAtMs);
    final targetManualImportanceNudgeScore = clearManualImportanceNudgeScore
        ? (ignoreClearManualNudges
            ? (existing.manualImportanceNudgeScore ?? 0)
            : 0)
        : (manualImportanceNudgeScore ??
            existing.manualImportanceNudgeScore ??
            0);
    final targetManualUrgencyNudgeScore = clearManualUrgencyNudgeScore
        ? (ignoreClearManualNudges
            ? (existing.manualUrgencyNudgeScore ?? 0)
            : 0)
        : (manualUrgencyNudgeScore ?? existing.manualUrgencyNudgeScore ?? 0);

    if (targetDueAtMs == existing.dueAtMs &&
        targetStatus == existing.status &&
        targetReviewStage == existing.reviewStage &&
        targetNextReviewAtMs == existing.nextReviewAtMs &&
        targetLastReviewAtMs == existing.lastReviewAtMs &&
        targetManualImportanceNudgeScore ==
            (existing.manualImportanceNudgeScore ?? 0) &&
        targetManualUrgencyNudgeScore ==
            (existing.manualUrgencyNudgeScore ?? 0)) {
      return existing;
    }

    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: targetDueAtMs,
      status: targetStatus,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: targetReviewStage,
      nextReviewAtMs: targetNextReviewAtMs,
      lastReviewAtMs: targetLastReviewAtMs,
      manualImportanceNudgeScore: targetManualImportanceNudgeScore,
      manualUrgencyNudgeScore: targetManualUrgencyNudgeScore,
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    final existing = _todosById[todoId]!;
    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: newStatus,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
      manualImportanceNudgeScore: existing.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: existing.manualUrgencyNudgeScore,
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async {
    return List<TodoChecklistItem>.from(
      _checklistItemsByTodoId[todoId] ?? const <TodoChecklistItem>[],
    );
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    deleteTodoCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) return;
    _todosById[todoId] = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: 'dismissed',
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
      manualImportanceNudgeScore: existing.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: existing.manualUrgencyNudgeScore,
    );
  }

  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    bool manualOverrideFollowup = false,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueueTodoFollowupGenerationJobCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
