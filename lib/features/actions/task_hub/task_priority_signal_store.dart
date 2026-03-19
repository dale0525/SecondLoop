import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class TaskPrioritySignalMutation {
  const TaskPrioritySignalMutation({
    required this.previous,
    required this.updated,
  });

  final TaskPriorityManualSignal? previous;
  final TaskPriorityManualSignal updated;
}

class TaskPriorityManualSignal {
  const TaskPriorityManualSignal({
    int importanceScore = 0,
    int urgencyScore = 0,
    bool? isImportant,
    bool? isUrgent,
    this.preferredStatus,
  })  : importanceScore = importanceScore != 0
            ? importanceScore
            : (isImportant == null ? 0 : (isImportant ? 1 : -1)),
        urgencyScore = urgencyScore != 0
            ? urgencyScore
            : (isUrgent == null ? 0 : (isUrgent ? 1 : -1));

  final int importanceScore;
  final int urgencyScore;
  final String? preferredStatus;

  bool get isEmpty =>
      importanceScore == 0 && urgencyScore == 0 && preferredStatus == null;

  bool? get isImportant {
    if (importanceScore > 0) return true;
    if (importanceScore < 0) return false;
    return null;
  }

  bool? get isUrgent {
    if (urgencyScore > 0) return true;
    if (urgencyScore < 0) return false;
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'importance_score': importanceScore,
      'urgency_score': urgencyScore,
      'preferred_status': preferredStatus,
    };
  }

  factory TaskPriorityManualSignal.fromJson(Map<String, Object?> json) {
    int? readInt(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse((raw ?? '').toString().trim());
    }

    bool? readBool(String key) {
      final raw = json[key];
      if (raw is bool) return raw;
      if (raw is String) {
        final normalized = raw.trim().toLowerCase();
        if (normalized == 'true') return true;
        if (normalized == 'false') return false;
      }
      return null;
    }

    return TaskPriorityManualSignal(
      importanceScore: readInt('importance_score') ??
          switch (readBool('is_important')) {
            true => 1,
            false => -1,
            null => 0,
          },
      urgencyScore: readInt('urgency_score') ??
          switch (readBool('is_urgent')) {
            true => 1,
            false => -1,
            null => 0,
          },
      preferredStatus:
          (json['preferred_status'] ?? '').toString().trim().isEmpty
              ? null
              : (json['preferred_status'] ?? '').toString().trim(),
    );
  }

  TaskPriorityManualSignal copyWith({
    int? importanceScore,
    int? urgencyScore,
    String? preferredStatus,
    int importanceDelta = 0,
    int urgencyDelta = 0,
    bool resetImportanceScore = false,
    bool resetUrgencyScore = false,
    bool clearPreferredStatus = false,
  }) {
    return TaskPriorityManualSignal(
      importanceScore: resetImportanceScore
          ? 0
          : (importanceScore ?? this.importanceScore) + importanceDelta,
      urgencyScore: resetUrgencyScore
          ? 0
          : (urgencyScore ?? this.urgencyScore) + urgencyDelta,
      preferredStatus: clearPreferredStatus
          ? null
          : (preferredStatus ?? this.preferredStatus),
    );
  }
}

class TaskPriorityManualSignalState {
  const TaskPriorityManualSignalState({
    this.byTodoId = const <String, TaskPriorityManualSignal>{},
  });

  final Map<String, TaskPriorityManualSignal> byTodoId;

  TaskPriorityManualSignal? operator [](String todoId) => byTodoId[todoId];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'todos': byTodoId.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  factory TaskPriorityManualSignalState.fromJson(Map<String, Object?> json) {
    final rawTodos = json['todos'];
    if (rawTodos is! Map) {
      return const TaskPriorityManualSignalState();
    }
    final byTodoId = <String, TaskPriorityManualSignal>{};
    for (final entry in rawTodos.entries) {
      final todoId = entry.key.toString().trim();
      if (todoId.isEmpty || entry.value is! Map) continue;
      byTodoId[todoId] = TaskPriorityManualSignal.fromJson(
        (entry.value as Map)
            .map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return TaskPriorityManualSignalState(byTodoId: byTodoId);
  }
}

class TaskPrioritySignalStore {
  const TaskPrioritySignalStore({this.scopeKey});

  static const _prefsKey = 'task_priority_manual_signals_v1';
  static Future<void>? _pendingMutation;
  final String? scopeKey;

  String get _scopedPrefsKey {
    final normalizedScopeKey = scopeKey?.trim();
    if (normalizedScopeKey == null || normalizedScopeKey.isEmpty) {
      return _prefsKey;
    }
    return '$_prefsKey:${base64UrlEncode(utf8.encode(normalizedScopeKey))}';
  }

  @visibleForTesting
  static void resetMutationQueueForTest() {
    _pendingMutation = null;
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final pending = _pendingMutation ?? Future<void>.value();
    _pendingMutation = pending.catchError((_) {}).then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<TaskPriorityManualSignalState> readManualState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const TaskPriorityManualSignalState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return TaskPriorityManualSignalState.fromJson(decoded);
      }
      if (decoded is Map) {
        return TaskPriorityManualSignalState.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return const TaskPriorityManualSignalState();
    }
    return const TaskPriorityManualSignalState();
  }

  Future<TaskPriorityManualSignal?> readForTodo(String todoId) async {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return null;
    final state = await readManualState();
    return state.byTodoId[trimmedTodoId];
  }

  Future<void> setForTodo(
      String todoId, TaskPriorityManualSignal signal) async {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return;
    await _enqueueMutation<void>(() async {
      final state = await readManualState();
      final next = Map<String, TaskPriorityManualSignal>.from(state.byTodoId);
      if (signal.isEmpty) {
        next.remove(trimmedTodoId);
      } else {
        next[trimmedTodoId] = signal;
      }
      await _write(TaskPriorityManualSignalState(byTodoId: next));
    });
  }

  Future<TaskPrioritySignalMutation> mutateForTodo(
    String todoId,
    TaskPriorityManualSignal Function(TaskPriorityManualSignal current) mutate,
  ) {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) {
      return Future.value(
        const TaskPrioritySignalMutation(
          previous: null,
          updated: TaskPriorityManualSignal(),
        ),
      );
    }

    return _enqueueMutation<TaskPrioritySignalMutation>(() async {
      final state = await readManualState();
      final previous = state.byTodoId[trimmedTodoId];
      final updated = mutate(previous ?? const TaskPriorityManualSignal());
      final next = Map<String, TaskPriorityManualSignal>.from(state.byTodoId);
      if (updated.isEmpty) {
        next.remove(trimmedTodoId);
      } else {
        next[trimmedTodoId] = updated;
      }
      await _write(TaskPriorityManualSignalState(byTodoId: next));
      return TaskPrioritySignalMutation(
        previous: previous,
        updated: updated,
      );
    });
  }

  Future<TaskPriorityManualSignal> adjustImportance(
    String todoId, {
    required bool increase,
  }) async {
    final mutation = await mutateForTodo(
      todoId,
      (current) => current.copyWith(importanceDelta: increase ? 1 : -1),
    );
    return mutation.updated;
  }

  Future<TaskPriorityManualSignal> adjustUrgency(
    String todoId, {
    required bool increase,
  }) async {
    final mutation = await mutateForTodo(
      todoId,
      (current) => current.copyWith(urgencyDelta: increase ? 1 : -1),
    );
    return mutation.updated;
  }

  Future<TaskPriorityManualSignal> setUrgency(
    String todoId, {
    required bool? isUrgent,
  }) async {
    final mutation = await mutateForTodo(
      todoId,
      (current) => isUrgent == null
          ? current.copyWith(resetUrgencyScore: true)
          : current.copyWith(urgencyScore: isUrgent ? 1 : -1),
    );
    return mutation.updated;
  }

  Future<TaskPriorityManualSignal?> clearPreferredStatusForTodo(
    String todoId,
  ) async {
    final mutation = await mutateForTodo(
      todoId,
      (current) => current.preferredStatus == null
          ? current
          : current.copyWith(clearPreferredStatus: true),
    );
    return mutation.previous;
  }

  Future<void> restoreForTodo(
    String todoId,
    TaskPriorityManualSignal? previous,
  ) async {
    if (previous == null || previous.isEmpty) {
      await setForTodo(todoId, const TaskPriorityManualSignal());
      return;
    }
    await setForTodo(todoId, previous);
  }

  Future<void> pruneToTodoIds(Iterable<String> todoIds) async {
    final allowed = todoIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    await _enqueueMutation<void>(() async {
      final state = await readManualState();
      final next = <String, TaskPriorityManualSignal>{};
      for (final entry in state.byTodoId.entries) {
        if (allowed.contains(entry.key)) {
          next[entry.key] = entry.value;
        }
      }
      if (next.length == state.byTodoId.length) return;
      await _write(TaskPriorityManualSignalState(byTodoId: next));
    });
  }

  Future<void> _write(TaskPriorityManualSignalState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedPrefsKey, jsonEncode(state.toJson()));
  }
}

String buildTaskPrioritySignalScopeKey(List<int> sessionKey) {
  return base64UrlEncode(sessionKey);
}
