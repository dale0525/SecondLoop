import 'dart:convert';

import 'todo_command_ai_prompts.dart';
import 'todo_command_models.dart';

enum TodoCommandAiRoute {
  byok,
  cloud,
}

abstract interface class TodoCommandAiPromptClient {
  Future<String> runTodoCommandPrompt({
    required String prompt,
    required TodoCommandAiRoute route,
  });
}

final class TodoCommandAiCandidate {
  const TodoCommandAiCandidate({
    required this.id,
    required this.title,
    required this.status,
    this.dueLocalIso,
    this.manualImportanceNudgeScore,
    this.manualUrgencyNudgeScore,
  });

  final String id;
  final String title;
  final String status;
  final String? dueLocalIso;
  final int? manualImportanceNudgeScore;
  final int? manualUrgencyNudgeScore;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'status': status,
      'due_local_iso': dueLocalIso,
      'manual_importance_nudge_score': manualImportanceNudgeScore,
      'manual_urgency_nudge_score': manualUrgencyNudgeScore,
    };
  }
}

final class TodoCommandAiService {
  const TodoCommandAiService({required TodoCommandAiPromptClient promptClient})
      : _promptClient = promptClient;

  final TodoCommandAiPromptClient _promptClient;

  Future<SecretaryTodoCommand?> parseTodoCommand({
    required String text,
    required DateTime nowLocal,
    required String localeTag,
    required List<TodoCommandAiCandidate> candidates,
    required TodoCommandAiRoute route,
    required String sourceMessageId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final prompt = TodoCommandAiPrompts.parseTodoCommand(
      text: text,
      nowLocal: nowLocal,
      localeTag: localeTag,
      candidates: candidates,
    );
    final raw = await _promptClient
        .runTodoCommandPrompt(prompt: prompt, route: route)
        .timeout(timeout);
    return commandFromJson(
      _decodeJsonObject(raw),
      candidates: candidates,
      route: route,
      sourceMessageId: sourceMessageId,
      rawText: text,
    );
  }

  static SecretaryTodoCommand? commandFromJson(
    Map<String, Object?> json, {
    required List<TodoCommandAiCandidate> candidates,
    required TodoCommandAiRoute route,
    required String sourceMessageId,
    required String rawText,
  }) {
    final kind = _kindFromWire(_stringValue(json['kind']));
    if (kind == SecretaryTodoCommandKind.none) return null;

    final candidateIds = {
      for (final candidate in candidates) candidate.id.trim()
    };
    final targetTodoId = _stringValue(json['target_todo_id']);
    if (targetTodoId != null && !candidateIds.contains(targetTodoId)) {
      return null;
    }

    final dueLocalIso = _stringValue(json['due_local_iso']);
    final dueAtMs = dueLocalIso == null
        ? null
        : DateTime.tryParse(dueLocalIso)?.millisecondsSinceEpoch;
    final command = SecretaryTodoCommand(
      id: 'todo-command-ai-$sourceMessageId',
      kind: kind,
      route: switch (route) {
        TodoCommandAiRoute.byok => SecretaryTodoCommandRoute.byok,
        TodoCommandAiRoute.cloud => SecretaryTodoCommandRoute.cloud,
      },
      confidence: _doubleValue(json['confidence']) ?? 0,
      sourceMessageId: sourceMessageId,
      targetTodoId: targetTodoId,
      targetTitle: _targetTitleFor(targetTodoId, candidates),
      newTitle: _stringValue(json['new_title']),
      newStatus: _stringValue(json['new_status']),
      dueAtMs: dueAtMs,
      manualImportanceNudgeScore:
          _intValue(json['manual_importance_nudge_score']),
      manualUrgencyNudgeScore: _intValue(json['manual_urgency_nudge_score']),
      reason: _stringValue(json['reason']),
      rawText: rawText,
    );
    return command.isValid ? command : null;
  }

  static Map<String, Object?> _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(trimmed.substring(start, end + 1));
        if (decoded is Map) return decoded.cast<String, Object?>();
      } catch (_) {
        return const <String, Object?>{};
      }
    }
    return const <String, Object?>{};
  }

  static SecretaryTodoCommandKind _kindFromWire(String? value) {
    return switch ((value ?? '').trim()) {
      'create' => SecretaryTodoCommandKind.create,
      'update_title' => SecretaryTodoCommandKind.updateTitle,
      'reschedule' => SecretaryTodoCommandKind.reschedule,
      'set_status' => SecretaryTodoCommandKind.setStatus,
      'dismiss' || 'delete' => SecretaryTodoCommandKind.dismiss,
      'reprioritize' => SecretaryTodoCommandKind.reprioritize,
      'batch_update' => SecretaryTodoCommandKind.batchUpdate,
      _ => SecretaryTodoCommandKind.none,
    };
  }

  static String? _targetTitleFor(
    String? targetTodoId,
    List<TodoCommandAiCandidate> candidates,
  ) {
    if (targetTodoId == null) return null;
    for (final candidate in candidates) {
      if (candidate.id == targetTodoId) return candidate.title;
    }
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
