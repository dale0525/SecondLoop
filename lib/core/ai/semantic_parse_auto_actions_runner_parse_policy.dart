part of 'semantic_parse_auto_actions_runner.dart';

String _localResultJson(LocalSemanticParseResult result) {
  return jsonEncode(<String, Object?>{
    'kind': switch (result.kind) {
      LocalSemanticParseKind.none => 'none',
      LocalSemanticParseKind.create => 'create',
      LocalSemanticParseKind.followup => 'followup',
    },
    'confidence': result.confidence,
    'resolver': switch (result.resolver) {
      SemanticResolver.local => 'local',
      SemanticResolver.llm => 'llm',
      SemanticResolver.hybrid => 'hybrid',
    },
    'title': result.title,
    'status': result.status,
    'todo_id': result.todoId,
    'due_local_iso': result.dueAtLocal?.toIso8601String(),
    'recurrence': result.recurrenceRule?.toJsonMap(),
    'task_type': result.taskType,
    'suggested_tags': result.suggestedTags,
    'tag_confidence': result.tagConfidence,
    'todo_command': result.todoCommand?.toJson(),
    'diagnostics': <String, Object?>{
      'local_intent': result.diagnostics.localIntent,
      'has_explicit_status_update': result.diagnostics.hasExplicitStatusUpdate,
      'has_due_signal': result.diagnostics.hasDueSignal,
      'temporal_needs_enhancement': result.diagnostics.temporalNeedsEnhancement,
      'semantic_needs_enhancement': result.diagnostics.semanticNeedsEnhancement,
      'looks_like_followup_edit': result.diagnostics.looksLikeFollowupEdit,
      'todo_command_intent': result.diagnostics.todoCommandIntent,
      'todo_command_needs_enhancement':
          result.diagnostics.todoCommandNeedsEnhancement,
      'todo_command_ambiguous': result.diagnostics.todoCommandAmbiguous,
    },
  });
}

List<String> _unresolvedFields(LocalSemanticParseResult result) {
  final fields = <String>[];

  void add(String value) {
    if (!fields.contains(value)) {
      fields.add(value);
    }
  }

  switch (result.kind) {
    case LocalSemanticParseKind.create:
      if ((result.title ?? '').trim().isEmpty) add('title');
      if ((result.status ?? '').trim().isEmpty) add('status');
      if (result.diagnostics.temporalNeedsEnhancement) add('due_local_iso');
      if (_isTaskTypeMissing(result.taskType)) add('task_type');
      if (result.suggestedTags.isEmpty) add('suggested_tags');
      break;
    case LocalSemanticParseKind.followup:
      if ((result.todoId ?? '').trim().isEmpty) add('todo_id');
      if ((result.status ?? '').trim().isEmpty && result.dueAtLocal == null) {
        add('new_status');
      }
      break;
    case LocalSemanticParseKind.none:
      switch (result.diagnostics.localIntent) {
        case 'ambiguous_todo_command':
          add('target_todo_id');
          add('kind');
          break;
        case 'todo_command':
          if (result.diagnostics.todoCommandNeedsEnhancement) {
            add('kind');
            add('target_todo_id');
          }
          break;
        case 'ambiguous_followup':
          add('todo_id');
          if (result.diagnostics.hasExplicitStatusUpdate) {
            add('new_status');
          }
          if (result.diagnostics.hasDueSignal ||
              result.diagnostics.temporalNeedsEnhancement) {
            add('due_local_iso');
          }
          break;
        case 'needs_enhancement':
          add('kind');
          if (result.diagnostics.semanticNeedsEnhancement) {
            add('title');
            add('status');
            add('todo_id');
          }
          if (result.diagnostics.hasExplicitStatusUpdate) {
            add('new_status');
          }
          if (result.diagnostics.hasDueSignal ||
              result.diagnostics.temporalNeedsEnhancement) {
            add('due_local_iso');
          }
          break;
        default:
          add('kind');
      }
      break;
  }

  return fields;
}

bool _shouldRequestEnhancement(
  LocalSemanticParseResult result, {
  required double minAutoConfidence,
}) {
  if (result.kind == LocalSemanticParseKind.create &&
      result.diagnostics.temporalNeedsEnhancement) {
    return true;
  }

  if (result.kind == LocalSemanticParseKind.create &&
      _createNeedsMetadataEnhancement(result)) {
    return true;
  }

  if (result.confidence < minAutoConfidence) {
    if (result.diagnostics.localIntent == 'todo_command' &&
        result.todoCommand != null &&
        !result.diagnostics.todoCommandNeedsEnhancement) {
      return false;
    }
    return true;
  }

  return switch (result.kind) {
    LocalSemanticParseKind.create => false,
    LocalSemanticParseKind.followup => false,
    LocalSemanticParseKind.none =>
      result.diagnostics.localIntent == 'todo_command'
          ? result.diagnostics.todoCommandNeedsEnhancement
          : result.diagnostics.localIntent != 'none',
  };
}

LocalSemanticParseResult _parseLocally({
  required String messageId,
  required String text,
  required DateTime nowLocal,
  required Locale locale,
  required List<SemanticParseTodoCandidate> candidates,
  required int dayEndMinutes,
  required int morningMinutes,
  required int firstDayOfWeekIndex,
  List<TodoThreadMatch> semanticMatches = const <TodoThreadMatch>[],
}) {
  final localTargets = candidates
      .map(
        (c) => TodoLinkTarget(
          id: c.id,
          title: c.title,
          status: c.status,
          dueLocal:
              c.dueLocalIso == null ? null : DateTime.tryParse(c.dueLocalIso!),
        ),
      )
      .toList(growable: false);

  return LocalSemanticParser.parse(
    text: text,
    messageId: messageId,
    nowLocal: nowLocal,
    locale: locale,
    openTodoTargets: localTargets,
    dayEndMinutes: dayEndMinutes,
    morningMinutes: morningMinutes,
    firstDayOfWeekIndex: firstDayOfWeekIndex,
    semanticMatches: semanticMatches,
  );
}

bool _shouldRetrieveSemanticCandidates(LocalSemanticParseResult result) {
  if (_isSuspiciousLocalCreate(result)) {
    return true;
  }
  if (result.kind != LocalSemanticParseKind.none) {
    return false;
  }
  final diagnostics = result.diagnostics;
  return switch (diagnostics.localIntent) {
    'ambiguous_todo_command' => true,
    'ambiguous_followup' => true,
    'needs_enhancement' => diagnostics.semanticNeedsEnhancement ||
        _looksLikeUnresolvedFollowupAutomation(diagnostics),
    'none' => _looksLikeUnresolvedFollowupAutomation(diagnostics),
    _ => false,
  };
}

bool _looksLikeUnresolvedFollowupAutomation(
  LocalSemanticParseDiagnostics diagnostics,
) {
  if (diagnostics.hasExplicitStatusUpdate) {
    return true;
  }
  if (!diagnostics.looksLikeFollowupEdit) {
    return false;
  }
  return diagnostics.hasDueSignal || diagnostics.temporalNeedsEnhancement;
}

bool _isSuspiciousLocalCreate(LocalSemanticParseResult result) {
  if (result.kind != LocalSemanticParseKind.create) {
    return false;
  }
  if (!result.diagnostics.looksLikeFollowupEdit) {
    return false;
  }
  return _looksLikeDeicticOnlyLocalTitle(result.title);
}

bool _looksLikeDeicticOnlyLocalTitle(String? text) {
  if (text == null) {
    return true;
  }
  return isDeicticOnlyTodoTitle(text);
}

List<String> _preferredTodoIdsFromSemanticMatches(
  List<TodoThreadMatch> semanticMatches,
) {
  final seen = <String>{};
  final preferredTodoIds = <String>[];
  for (final match in semanticMatches) {
    final todoId = match.todoId.trim();
    if (todoId.isEmpty || !seen.add(todoId)) continue;
    preferredTodoIds.add(todoId);
  }
  return preferredTodoIds;
}

bool _isTaskTypeMissing(String? taskType) {
  final normalized = taskType?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty || normalized == 'unknown';
}

bool _createNeedsMetadataEnhancement(LocalSemanticParseResult result) {
  if (result.kind != LocalSemanticParseKind.create) {
    return false;
  }
  final inferredTaskType =
      classifyTodoFollowupTaskType(result.title ?? '').wireValue;
  return inferredTaskType == TodoFollowupTaskType.research.wireValue ||
      inferredTaskType == TodoFollowupTaskType.comparison.wireValue ||
      inferredTaskType == TodoFollowupTaskType.liveInfoLookup.wireValue ||
      inferredTaskType == TodoFollowupTaskType.referenceCollection.wireValue;
}

bool _isMetadataOnlyEnhancement(List<String> unresolvedFields) {
  const actionFields = <String>{
    'kind',
    'title',
    'status',
    'todo_id',
    'new_status',
    'due_local_iso',
  };
  for (final field in unresolvedFields) {
    if (actionFields.contains(field)) {
      return false;
    }
  }
  return true;
}

AiSemanticDecision _mergeEnhancedDecision({
  required LocalSemanticParseResult localResult,
  required AiSemanticDecision remoteParsed,
  required List<String> unresolvedFields,
}) {
  if (!_isMetadataOnlyEnhancement(unresolvedFields)) {
    return remoteParsed;
  }

  final localParsed = AiSemanticParse.fromLocalResult(localResult);
  final mergedTags = remoteParsed.suggestedTags.isNotEmpty
      ? remoteParsed.suggestedTags
      : localParsed.suggestedTags;
  final mergedTagConfidence = remoteParsed.suggestedTags.isNotEmpty
      ? remoteParsed.tagConfidence
      : localParsed.tagConfidence;
  final mergedTaskType = _isTaskTypeMissing(remoteParsed.taskType)
      ? localParsed.taskType
      : remoteParsed.taskType;

  return AiSemanticDecision(
    decision: localParsed.decision,
    confidence: remoteParsed.confidence > localParsed.confidence
        ? remoteParsed.confidence
        : localParsed.confidence,
    taskType: mergedTaskType,
    suggestedTags: mergedTags,
    tagConfidence: mergedTagConfidence,
  );
}
