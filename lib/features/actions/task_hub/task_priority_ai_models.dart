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
  });

  final String todoId;
  final TaskPriorityAiBand priorityBand;
  final double semanticAdjustment;
  final String reason;
  final TaskPrioritySuggestionKind suggestedAction;
  final TaskPriorityAiConfidence confidence;

  factory TaskPriorityAiEntry.fromJson(Map<String, Object?> json) {
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
    );
  }
}

class TaskPriorityAiBatchResult {
  const TaskPriorityAiBatchResult({required this.entries});

  const TaskPriorityAiBatchResult.empty()
      : entries = const <TaskPriorityAiEntry>[];

  final List<TaskPriorityAiEntry> entries;
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'todo_id': todoId,
      'title': title,
      'status': status,
      'band': band.name,
      'due_state': dueState,
      'rule_score': ruleScore,
      'updated_at_ms': updatedAtMs,
      'recent_interaction_summary': recentInteractionSummary,
      'source_summary': sourceSummary,
      'is_repeatedly_deferred': isRepeatedlyDeferred,
      'is_potential_blocker': isPotentialBlocker,
      'is_quick_win': isQuickWin,
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
