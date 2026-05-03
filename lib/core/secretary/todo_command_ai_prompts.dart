import 'dart:convert';

import 'todo_command_ai_service.dart';

final class TodoCommandAiPrompts {
  const TodoCommandAiPrompts._();

  static String parseTodoCommand({
    required String text,
    required DateTime nowLocal,
    required String localeTag,
    required List<TodoCommandAiCandidate> candidates,
  }) {
    return jsonEncode(<String, Object?>{
      'purpose': 'semantic_parse',
      'task': 'parse_todo_command',
      'locale': localeTag,
      'now_local_iso': nowLocal.toIso8601String(),
      'rules': const <String>[
        'Return JSON only.',
        'Do not apply mutations.',
        'Only choose target ids from provided candidates.',
        'Use kind none when target is ambiguous.',
        'Do not invent todos or memory.',
      ],
      'response_schema': <String, Object?>{
        'kind':
            'create|update_title|reschedule|set_status|dismiss|reprioritize|batch_update|none',
        'confidence': 'number',
        'target_todo_id': 'string|null',
        'new_title': 'string|null',
        'new_status': 'string|null',
        'due_local_iso': 'string|null',
        'manual_importance_nudge_score': 'number|null',
        'manual_urgency_nudge_score': 'number|null',
        'requires_confirmation': 'boolean',
      },
      'text': text,
      'candidates': [
        for (final candidate in candidates.take(16)) candidate.toJson(),
      ],
    });
  }
}
