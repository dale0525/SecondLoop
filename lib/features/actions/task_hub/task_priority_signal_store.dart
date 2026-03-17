import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TaskPriorityManualSignal {
  const TaskPriorityManualSignal({
    this.isImportant,
    this.isUrgent,
  });

  final bool? isImportant;
  final bool? isUrgent;

  bool get isEmpty => isImportant == null && isUrgent == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'is_important': isImportant,
      'is_urgent': isUrgent,
    };
  }

  factory TaskPriorityManualSignal.fromJson(Map<String, Object?> json) {
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
      isImportant: readBool('is_important'),
      isUrgent: readBool('is_urgent'),
    );
  }

  TaskPriorityManualSignal copyWith({
    bool? isImportant,
    bool? isUrgent,
    bool clearImportant = false,
    bool clearUrgent = false,
  }) {
    return TaskPriorityManualSignal(
      isImportant: clearImportant ? null : (isImportant ?? this.isImportant),
      isUrgent: clearUrgent ? null : (isUrgent ?? this.isUrgent),
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
  const TaskPrioritySignalStore();

  static const _prefsKey = 'task_priority_manual_signals_v1';

  Future<TaskPriorityManualSignalState> readManualState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
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
    final state = await readManualState();
    final next = Map<String, TaskPriorityManualSignal>.from(state.byTodoId);
    if (signal.isEmpty) {
      next.remove(trimmedTodoId);
    } else {
      next[trimmedTodoId] = signal;
    }
    await _write(TaskPriorityManualSignalState(byTodoId: next));
  }

  Future<TaskPriorityManualSignal> adjustImportance(
    String todoId, {
    required bool increase,
  }) async {
    final current =
        await readForTodo(todoId) ?? const TaskPriorityManualSignal();
    final updated = current.copyWith(isImportant: increase);
    await setForTodo(todoId, updated);
    return updated;
  }

  Future<TaskPriorityManualSignal> adjustUrgency(
    String todoId, {
    required bool increase,
  }) async {
    final current =
        await readForTodo(todoId) ?? const TaskPriorityManualSignal();
    final updated = current.copyWith(isUrgent: increase);
    await setForTodo(todoId, updated);
    return updated;
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
    final state = await readManualState();
    final next = <String, TaskPriorityManualSignal>{};
    for (final entry in state.byTodoId.entries) {
      if (allowed.contains(entry.key)) {
        next[entry.key] = entry.value;
      }
    }
    if (next.length == state.byTodoId.length) return;
    await _write(TaskPriorityManualSignalState(byTodoId: next));
  }

  Future<void> _write(TaskPriorityManualSignalState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }
}
