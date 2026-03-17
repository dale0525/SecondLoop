import 'dart:convert';

import 'task_priority_models.dart';

enum TaskPriorityAiBand {
  focus,
  next,
  later,
}

enum TaskPriorityAiConfidence {
  low,
  medium,
  high,
}

class TaskPriorityAiEntry {
  const TaskPriorityAiEntry({
    required this.todoId,
    required this.priorityBand,
    required this.semanticAdjustment,
    required this.reason,
    required this.suggestedAction,
    required this.confidence,
    this.isImportant,
    this.isUrgent,
  });

  final String todoId;
  final TaskPriorityAiBand priorityBand;
  final double semanticAdjustment;
  final String reason;
  final TaskPrioritySuggestionKind suggestedAction;
  final TaskPriorityAiConfidence confidence;
  final bool? isImportant;
  final bool? isUrgent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'todo_id': todoId,
      'priority_band': priorityBand.name,
      'semantic_adjustment': semanticAdjustment,
      'reason': reason,
      'suggested_action': suggestedAction.name,
      'confidence': confidence.name,
      'is_important': isImportant,
      'is_urgent': isUrgent,
    };
  }

  factory TaskPriorityAiEntry.fromJson(Map<String, Object?> json) {
    bool? parseBool(Object? raw) {
      if (raw is bool) return raw;
      final text = raw?.toString().trim().toLowerCase();
      if (text == 'true') return true;
      if (text == 'false') return false;
      return null;
    }

    final todoId = (json['todo_id'] ?? json['todoId'] ?? '').toString().trim();
    final priorityBand = switch (
        (json['priority_band'] ?? json['priorityBand'] ?? '')
            .toString()
            .trim()
            .toLowerCase()) {
      'focus' => TaskPriorityAiBand.focus,
      'later' => TaskPriorityAiBand.later,
      _ => TaskPriorityAiBand.next,
    };
    final suggestedActionToken =
        (json['suggested_action'] ?? json['suggestedAction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final suggestedAction = switch (suggestedActionToken) {
      'schedule' => TaskPrioritySuggestionKind.schedule,
      'defer' => TaskPrioritySuggestionKind.defer,
      'clarify' => TaskPrioritySuggestionKind.clarify,
      _ => TaskPrioritySuggestionKind.doNow,
    };
    final confidence =
        switch ((json['confidence'] ?? '').toString().trim().toLowerCase()) {
      'high' => TaskPriorityAiConfidence.high,
      'medium' => TaskPriorityAiConfidence.medium,
      _ => TaskPriorityAiConfidence.low,
    };
    final adjustmentRaw = json['semantic_adjustment'] ?? json['semanticScore'];
    final adjustment = adjustmentRaw is num
        ? adjustmentRaw.toDouble()
        : double.tryParse(adjustmentRaw?.toString() ?? '') ?? 0;
    return TaskPriorityAiEntry(
      todoId: todoId,
      priorityBand: priorityBand,
      semanticAdjustment: adjustment,
      reason: (json['reason'] ?? '').toString().trim(),
      suggestedAction: suggestedAction,
      confidence: confidence,
      isImportant: parseBool(json['is_important'] ?? json['important']),
      isUrgent: parseBool(json['is_urgent'] ?? json['urgent']),
    );
  }
}

class TaskPriorityAiBatchResult {
  const TaskPriorityAiBatchResult({required this.entries});

  const TaskPriorityAiBatchResult.empty()
      : entries = const <TaskPriorityAiEntry>[];

  final List<TaskPriorityAiEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  factory TaskPriorityAiBatchResult.fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      return const TaskPriorityAiBatchResult.empty();
    }
    final entries = <TaskPriorityAiEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map) continue;
      entries.add(
        TaskPriorityAiEntry.fromJson(
          rawEntry.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
    return TaskPriorityAiBatchResult(entries: entries);
  }
}

class TaskPriorityAiCandidate {
  const TaskPriorityAiCandidate({
    required this.todoId,
    required this.title,
    required this.status,
    required this.band,
    required this.dueState,
    required this.ruleScore,
    required this.updatedAtMs,
    required this.recentInteractionSummary,
    required this.sourceSummary,
    required this.isRepeatedlyDeferred,
    required this.isPotentialBlocker,
    required this.isQuickWin,
    required this.ruleIsImportant,
    required this.ruleIsUrgent,
  });

  final String todoId;
  final String title;
  final String status;
  final TaskPriorityBand band;
  final String dueState;
  final double ruleScore;
  final int updatedAtMs;
  final String recentInteractionSummary;
  final String sourceSummary;
  final bool isRepeatedlyDeferred;
  final bool isPotentialBlocker;
  final bool isQuickWin;
  final bool ruleIsImportant;
  final bool ruleIsUrgent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'todo_id': todoId,
      'title': title,
      'status': status,
      'band': band.name,
      'due_state': dueState,
      'rule_score': ruleScore,
      'recent_interaction_summary': recentInteractionSummary,
      'source_summary': sourceSummary,
      'is_repeatedly_deferred': isRepeatedlyDeferred,
      'is_potential_blocker': isPotentialBlocker,
      'is_quick_win': isQuickWin,
      'rule_is_important': ruleIsImportant,
      'rule_is_urgent': ruleIsUrgent,
    };
  }
}

class TaskPriorityAiRequest {
  const TaskPriorityAiRequest({
    required this.nowLocal,
    required this.candidates,
  });

  final DateTime nowLocal;
  final List<TaskPriorityAiCandidate> candidates;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'now_local_iso': nowLocal.toIso8601String(),
      'candidates':
          candidates.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  TaskPriorityAiRequest copyWith({
    DateTime? nowLocal,
    List<TaskPriorityAiCandidate>? candidates,
  }) {
    return TaskPriorityAiRequest(
      nowLocal: nowLocal ?? this.nowLocal,
      candidates: candidates ?? this.candidates,
    );
  }
}

String buildTaskPriorityAiTimeBucket(DateTime nowLocal) {
  return '${nowLocal.year.toString().padLeft(4, '0')}-'
      '${nowLocal.month.toString().padLeft(2, '0')}-'
      '${nowLocal.day.toString().padLeft(2, '0')}T'
      '${nowLocal.hour.toString().padLeft(2, '0')}';
}

TaskPriorityAiBatchResult parseTaskPriorityAiBatchResult(String raw) {
  final trimmed = raw.trim();
  final jsonText = _extractJsonObject(trimmed) ?? trimmed;
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('task_priority_ai_response_not_json_object');
  }
  final rawEntries = decoded['entries'];
  if (rawEntries is! List) {
    return const TaskPriorityAiBatchResult.empty();
  }
  final entries = <TaskPriorityAiEntry>[];
  for (final rawEntry in rawEntries) {
    if (rawEntry is! Map) continue;
    entries.add(
      TaskPriorityAiEntry.fromJson(
        rawEntry.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
  return TaskPriorityAiBatchResult(entries: entries);
}

String? _extractJsonObject(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return null;
  return raw.substring(start, end + 1);
}

String encodeTaskPriorityAiPrompt(TaskPriorityAiRequest request) {
  return jsonEncode(request.toJson());
}
