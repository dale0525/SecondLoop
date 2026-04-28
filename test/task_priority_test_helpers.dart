import 'dart:convert';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/src/rust/db.dart';

String stableTaskPriorityRequestSignatureFor(Todo todo, DateTime nowLocal) {
  final candidate = buildTaskPriorityAiRequest(
    buildTaskPrioritySnapshot(<Todo>[todo], nowLocal: nowLocal),
    nowLocal: nowLocal,
  ).candidates.single;
  return jsonEncode(<String, Object?>{
    'candidate': <String, Object?>{
      'todo_id': candidate.todoId,
      'title': candidate.title,
      'status': candidate.status,
      'band': candidate.band.name,
      'due_state': candidate.dueState,
      'source_summary': candidate.sourceSummary,
      'is_repeatedly_deferred': candidate.isRepeatedlyDeferred,
      'is_potential_blocker': candidate.isPotentialBlocker,
      'is_quick_win': candidate.isQuickWin,
      'rule_is_important': candidate.ruleIsImportant,
      'rule_is_urgent': candidate.ruleIsUrgent,
    },
  });
}
