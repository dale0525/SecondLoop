import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum TaskPriorityFeedbackKind {
  notImportant,
  recommendLater,
  decideMyself,
}

class TaskPriorityFeedbackState {
  const TaskPriorityFeedbackState({
    this.suppressedTodoIds = const <String>{},
    this.deprioritizedTodoIds = const <String>{},
  });

  final Set<String> suppressedTodoIds;
  final Set<String> deprioritizedTodoIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'suppressed_todo_ids': suppressedTodoIds.toList(growable: false),
      'deprioritized_todo_ids': deprioritizedTodoIds.toList(growable: false),
    };
  }

  static TaskPriorityFeedbackState fromJson(Map<String, Object?> json) {
    Set<String> decodeSet(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>{};
      return raw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }

    return TaskPriorityFeedbackState(
      suppressedTodoIds: decodeSet('suppressed_todo_ids'),
      deprioritizedTodoIds: decodeSet('deprioritized_todo_ids'),
    );
  }
}

class TaskPriorityFeedbackStore {
  const TaskPriorityFeedbackStore();

  static const _prefsKey = 'task_priority_feedback_v1';

  Future<TaskPriorityFeedbackState> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const TaskPriorityFeedbackState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return TaskPriorityFeedbackState.fromJson(decoded);
      }
      if (decoded is Map) {
        return TaskPriorityFeedbackState.fromJson(
          decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      }
    } catch (_) {
      return const TaskPriorityFeedbackState();
    }
    return const TaskPriorityFeedbackState();
  }

  Future<void> record({
    required String todoId,
    required TaskPriorityFeedbackKind feedback,
  }) async {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return;

    final current = await read();
    final suppressed = current.suppressedTodoIds.toSet();
    final deprioritized = current.deprioritizedTodoIds.toSet();

    switch (feedback) {
      case TaskPriorityFeedbackKind.notImportant:
        suppressed.add(trimmedTodoId);
        deprioritized.add(trimmedTodoId);
        break;
      case TaskPriorityFeedbackKind.recommendLater:
      case TaskPriorityFeedbackKind.decideMyself:
        suppressed.add(trimmedTodoId);
        break;
    }

    await _write(
      TaskPriorityFeedbackState(
        suppressedTodoIds: suppressed,
        deprioritizedTodoIds: deprioritized,
      ),
    );
  }

  Future<void> forget({required String todoId}) async {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return;

    final current = await read();
    final suppressed = current.suppressedTodoIds.toSet()..remove(trimmedTodoId);
    final deprioritized = current.deprioritizedTodoIds.toSet()
      ..remove(trimmedTodoId);
    await _write(
      TaskPriorityFeedbackState(
        suppressedTodoIds: suppressed,
        deprioritizedTodoIds: deprioritized,
      ),
    );
  }

  Future<void> pruneToTodoIds(Iterable<String> todoIds) async {
    final allowed = todoIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final current = await read();
    final suppressed = current.suppressedTodoIds
        .where((value) => allowed.contains(value))
        .toSet();
    final deprioritized = current.deprioritizedTodoIds
        .where((value) => allowed.contains(value))
        .toSet();
    if (suppressed.length == current.suppressedTodoIds.length &&
        deprioritized.length == current.deprioritizedTodoIds.length) {
      return;
    }
    await _write(
      TaskPriorityFeedbackState(
        suppressedTodoIds: suppressed,
        deprioritizedTodoIds: deprioritized,
      ),
    );
  }

  Future<void> _write(TaskPriorityFeedbackState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }
}
