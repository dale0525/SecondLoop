import 'dart:convert';

import '../../../src/rust/platform_int.dart';
import 'task_priority_models.dart';

class TaskPriorityStickyFocusState {
  String? _todoId;
  DateTime? _dayLocal;
  Map<String, String> _dueStateByTodoId = const <String, String>{};

  void remember(TaskPrioritySnapshot snapshot, DateTime nowLocal) {
    _todoId = snapshot.primaryFocus?.todo.id;
    _dayLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    _dueStateByTodoId = _buildStateSignatures(snapshot);
  }

  TaskPrioritySnapshot apply(
    TaskPrioritySnapshot snapshot, {
    required DateTime nowLocal,
  }) {
    final stickyTodoId = _todoId;
    final stickyDay = _dayLocal;
    if (stickyTodoId == null || stickyDay == null) return snapshot;

    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (today != stickyDay) return snapshot;
    final primary = snapshot.primaryFocus;
    if (primary == null || primary.todo.id == stickyTodoId) return snapshot;
    if (primary.hasHardFocusGuard ||
        primary.confidence == TaskPriorityConfidence.high) {
      return snapshot;
    }
    if (_didDueStateChange(snapshot)) return snapshot;

    final stickyExists = snapshot.activeEntries.any(
      (entry) => entry.todo.id == stickyTodoId,
    );
    if (!stickyExists) return snapshot;

    return snapshot.copyWith(selectedFocusTodoId: stickyTodoId);
  }

  Map<String, String> _buildStateSignatures(TaskPrioritySnapshot snapshot) {
    return <String, String>{
      for (final entry in snapshot.activeEntries)
        entry.todo.id: jsonEncode(<Object?>[
          entry.todo.status,
          platformIntToNullableInt(entry.todo.dueAtMs),
          platformIntToNullableInt(entry.todo.reviewStage),
          platformIntToNullableInt(entry.todo.nextReviewAtMs),
          entry.isOverdue,
          entry.isDueToday,
          entry.isReviewDue,
          entry.isFutureScheduled,
          entry.isInProgress,
          entry.effectiveUrgency,
          entry.effectiveImportance,
          entry.urgencyScore,
          entry.importanceScore,
          entry.dueDerivedUrgencyScore,
          _semanticDirection(entry.semanticScore),
          entry.isUrgent,
          entry.isImportant,
        ]),
    };
  }

  int _semanticDirection(double semanticScore) {
    if (semanticScore > 0) return 1;
    if (semanticScore < 0) return -1;
    return 0;
  }

  bool _didDueStateChange(TaskPrioritySnapshot snapshot) {
    final previous = _dueStateByTodoId;
    if (previous.isEmpty) return false;
    final current = _buildStateSignatures(snapshot);
    if (current.length != previous.length) return true;
    for (final entry in current.entries) {
      if (previous[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }
}
