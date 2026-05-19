import 'dart:convert';
import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../backend/secretary_backend.dart';
import 'secretary_runtime_client.dart';
import 'secretary_runtime_conversation_models.dart';
import 'secretary_runtime_conversation_sender.dart';

part 'runtime_secretary_app_service_memory.dart';

final class RuntimeSecretaryAppService {
  const RuntimeSecretaryAppService({
    required ChatRuntimeConversationSender sender,
    required AppBackend backend,
    required Uint8List sessionKey,
  })  : _sender = sender,
        _backend = backend,
        _sessionKey = sessionKey;

  final ChatRuntimeConversationSender _sender;
  final AppBackend _backend;
  final Uint8List _sessionKey;

  Future<SecretaryRuntimeConversationResult> sendAndApply({
    required String vaultId,
    required String conversationId,
    required String message,
    String? sourceMessageId,
  }) async {
    final result = await _sender.send(
      vaultId: vaultId,
      conversationId: conversationId,
      message: message,
    );
    await applyResult(
      result,
      conversationId: conversationId,
      sourceMessageId: sourceMessageId,
    );
    return result;
  }

  Future<void> applyResult(
    SecretaryRuntimeConversationResult result, {
    required String conversationId,
    String? sourceMessageId,
  }) async {
    final content = result.assistantContent.trim();
    if (content.isNotEmpty) {
      final citationsJson = _webResearchCitationsJson(result);
      final backend = _backend;
      if (citationsJson != null && backend is AssistantCitationWriteBackend) {
        await (backend as AssistantCitationWriteBackend)
            .insertAssistantMessageWithCitations(
          _sessionKey,
          conversationId,
          content: content,
          citationsJson: citationsJson,
        );
      } else {
        await backend.insertMessage(
          _sessionKey,
          conversationId,
          role: 'assistant',
          content: content,
        );
      }
    }
    await applyRuntimeTaskMutations(
      result,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId,
    );
    await applyRuntimeMemoryMutations(
      result,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId,
    );
    await applyRuntimeRecurringReminderMutations(
      result,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }

  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String conversationId,
    required String approvalId,
    required String decision,
    String? sourceMessageId,
  }) async {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    final result = await approvalSender.submitApprovalDecision(
      vaultId: vaultId,
      approvalId: approvalId,
      decision: decision,
    );
    if (result != null) {
      await applyResult(
        result,
        conversationId: conversationId,
        sourceMessageId: sourceMessageId,
      );
    }
    return result;
  }

  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovalItems({
    required String vaultId,
  }) {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    return approvalSender.fetchApprovals(vaultId: vaultId);
  }

  Future<SecretaryRuntimeApprovalItem> patchApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required Map<String, Object?> changes,
  }) {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    return approvalSender.patchApprovalItem(
      vaultId: vaultId,
      approvalId: item.id,
      baseVersion: item.version,
      changes: changes,
    );
  }

  Future<SecretaryRuntimeConversationResult?> approveApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required String conversationId,
    String? sourceMessageId,
  }) async {
    final result = await submitApprovalDecision(
      vaultId: vaultId,
      conversationId: conversationId,
      approvalId: item.id,
      decision: 'approve',
      sourceMessageId: sourceMessageId,
    );
    if (result == null || !_hasAppliedTaskMutation(result)) {
      await applyApprovedTaskMutation(item, sourceMessageId: sourceMessageId);
    }
    if (result == null || !_hasAppliedMemoryMutation(result)) {
      await applyApprovedMemoryConfirmation(
        item,
        sourceMessageId: sourceMessageId,
      );
    }
    if (result == null || !_hasAppliedRecurringReminderMutation(result)) {
      await applyApprovedRecurringReminderConfirmation(
        item,
        sourceMessageId: sourceMessageId,
      );
    }
    return result;
  }

  Future<void> rejectApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required String conversationId,
    String? sourceMessageId,
  }) {
    return submitApprovalDecision(
      vaultId: vaultId,
      conversationId: conversationId,
      approvalId: item.id,
      decision: 'reject',
      sourceMessageId: sourceMessageId,
    );
  }

  Future<void> applyApprovedTaskMutation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {
    if (item.kind != 'task_mutation_confirmation') return;
    final mutation = <String, Object?>{
      'entity_type': 'task',
      'mutation_type': 'update',
      'status': 'applied',
      'record_id': item.taskId,
      'record': item.record ?? const <String, Object?>{},
    };
    await _applyRuntimeTaskMutation(
      mutation,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }

  Future<void> applyApprovedMemoryConfirmation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {
    if (item.kind != 'memory_confirmation') return;
    final backend = _backend;
    if (backend is! SecretaryBackend) return;
    final secretaryBackend = backend as SecretaryBackend;
    final record = item.record ?? const <String, Object?>{};
    final title = _runtimeMemoryTitle(record, fallback: item.title);
    if (title == null) return;
    final body = _runtimeMemoryBody(record, fallback: title) ?? title;
    await _storeRuntimeMemoryCandidate(
      secretaryBackend,
      _sessionKey,
      title: title,
      body: body,
      kind: _runtimeMemoryKind(record),
      confidence: _runtimeDouble(record['confidence']) ?? 0.9,
      sourceMessageId: sourceMessageId ?? item.id,
      sourceRefsJson: _runtimeMemorySourceRefsJson(
        record,
        approvalId: item.id,
      ),
    );
  }

  Future<void> applyApprovedRecurringReminderConfirmation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {
    if (item.kind != 'recurring_reminder_confirmation') return;
    final record = <String, Object?>{
      ...item.record ?? const <String, Object?>{},
    };
    if (_runtimeString(record['id']) == null) {
      record['id'] = _runtimeString(item.recurringRuleId);
    }
    if (_runtimeString(record['title']) == null) {
      record['title'] = _runtimeString(item.title);
    }
    await _storeRuntimeRecurringReminderRule(
      record,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId ?? item.id,
    );
  }
}

Future<void> applyRuntimeTaskMutations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  for (final mutation in result.metadata.appliedMutations) {
    await _applyRuntimeTaskMutation(
      mutation,
      backend: backend,
      sessionKey: sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }
}

Future<void> applyRuntimeTaskCreations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) {
  return applyRuntimeTaskMutations(
    result,
    backend: backend,
    sessionKey: sessionKey,
    sourceMessageId: sourceMessageId,
  );
}

Future<void> applyRuntimeRecurringReminderMutations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  for (final mutation in result.metadata.appliedMutations) {
    await _applyRuntimeRecurringReminderMutation(
      mutation,
      backend: backend,
      sessionKey: sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }
}

Future<void> _applyRuntimeTaskMutation(
  Map<String, Object?> mutation, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  if (_runtimeString(mutation['entity_type']) != 'task') return;
  if (_runtimeString(mutation['status']) != 'applied') return;

  final mutationType =
      _runtimeString(mutation['mutation_type'])?.toLowerCase() ?? '';
  if (mutationType == 'create') {
    final record = _runtimeMap(mutation['record']);
    final id = _runtimeString(record['id']) ??
        _runtimeString(record['task_id']) ??
        _runtimeString(mutation['record_id']);
    final title = _runtimeString(record['title']);
    if (id == null || title == null) return;

    await backend.upsertTodo(
      sessionKey,
      id: id,
      title: title,
      dueAtMs: _runtimeDueAtMs(record),
      status: runtimeTodoStatus(record['status']),
      sourceEntryId: sourceMessageId,
      reviewStage: _runtimeInt(record['review_stage']) ??
          _runtimeInt(record['reviewStage']),
      nextReviewAtMs: _runtimeInt(record['next_review_at_ms']) ??
          _runtimeInt(record['nextReviewAtMs']),
      lastReviewAtMs: _runtimeInt(record['last_review_at_ms']) ??
          _runtimeInt(record['lastReviewAtMs']),
    );
    return;
  }

  if (mutationType != 'update' &&
      mutationType != 'reschedule' &&
      mutationType != 'rename' &&
      mutationType != 'status_update' &&
      mutationType != 'complete') {
    return;
  }

  final record = _runtimeMap(mutation['record']);
  final id = _runtimeString(record['id']) ??
      _runtimeString(record['task_id']) ??
      _runtimeString(record['todo_id']) ??
      _runtimeString(mutation['record_id']) ??
      _runtimeString(mutation['task_id']) ??
      _runtimeString(mutation['todo_id']);
  if (id == null) return;

  final dueAtMs = _runtimeDueAtMs(record, fallback: mutation);
  final clearDueAtMs = _runtimeBool(record['clear_due_at_ms']) ||
      _runtimeBool(record['clearDueAtMs']) ||
      _runtimeBool(mutation['clear_due_at_ms']) ||
      _runtimeBool(mutation['clearDueAtMs']);
  final status = runtimeTodoStatusOrNull(
        record['status'],
      ) ??
      runtimeTodoStatusOrNull(record['new_status']) ??
      runtimeTodoStatusOrNull(record['newStatus']) ??
      runtimeTodoStatusOrNull(mutation['status_value']);
  final title = _runtimeString(record['title']) ??
      _runtimeString(record['new_title']) ??
      _runtimeString(record['newTitle']);

  if (title != null) {
    await _upsertExistingTaskPatch(
      backend,
      sessionKey,
      todoId: id,
      title: title,
      dueAtMs: dueAtMs,
      clearDueAtMs: clearDueAtMs,
      status: status,
      sourceMessageId: sourceMessageId,
    );
    return;
  }

  if (dueAtMs == null && !clearDueAtMs && status == null) return;
  await backend.transitionTodo(
    sessionKey,
    todoId: id,
    newStatus: status,
    dueAtMs: dueAtMs,
    clearDueAtMs: clearDueAtMs,
    sourceMessageId: sourceMessageId,
  );
}

Future<void> _upsertExistingTaskPatch(
  AppBackend backend,
  Uint8List sessionKey, {
  required String todoId,
  required String title,
  int? dueAtMs,
  bool clearDueAtMs = false,
  String? status,
  String? sourceMessageId,
}) async {
  final current = await backend.getTodoById(sessionKey, todoId);
  await backend.upsertTodo(
    sessionKey,
    id: todoId,
    title: title,
    dueAtMs: clearDueAtMs
        ? null
        : dueAtMs ?? _platformIntToNullableInt(current?.dueAtMs),
    status: status ?? current?.status ?? 'open',
    sourceEntryId: current?.sourceEntryId ?? sourceMessageId,
    reviewStage: _platformIntToNullableInt(current?.reviewStage),
    nextReviewAtMs: _platformIntToNullableInt(current?.nextReviewAtMs),
    lastReviewAtMs: _platformIntToNullableInt(current?.lastReviewAtMs),
    manualImportanceNudgeScore:
        _platformIntToNullableInt(current?.manualImportanceNudgeScore),
    manualUrgencyNudgeScore:
        _platformIntToNullableInt(current?.manualUrgencyNudgeScore),
  );
}

int? _platformIntToNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  try {
    final converted = (value as dynamic).toInt();
    if (converted is int) return converted;
    if (converted is num) return converted.toInt();
  } catch (_) {
    return null;
  }
  return null;
}

String runtimeTodoStatus(Object? raw) {
  final status = _runtimeString(raw)?.toLowerCase();
  if (status == null ||
      status == 'todo' ||
      status == 'to_do' ||
      status == 'pending' ||
      status == 'not_started') {
    return 'open';
  }
  return status;
}

String? runtimeTodoStatusOrNull(Object? raw) {
  final status = _runtimeString(raw);
  return status == null ? null : runtimeTodoStatus(status);
}

bool _hasAppliedTaskMutation(SecretaryRuntimeConversationResult result) {
  return result.metadata.appliedMutations.any((mutation) {
    return _runtimeString(mutation['entity_type']) == 'task' &&
        _runtimeString(mutation['status']) == 'applied';
  });
}

bool _hasAppliedRecurringReminderMutation(
  SecretaryRuntimeConversationResult result,
) {
  return result.metadata.appliedMutations.any((mutation) {
    final entityType = _runtimeString(mutation['entity_type']);
    return _isRuntimeRecurringReminderEntity(entityType) &&
        _runtimeString(mutation['status']) == 'applied';
  });
}

Future<void> _applyRuntimeRecurringReminderMutation(
  Map<String, Object?> mutation, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  if (!_isRuntimeRecurringReminderEntity(
    _runtimeString(mutation['entity_type']),
  )) {
    return;
  }
  if (_runtimeString(mutation['status']) != 'applied') return;
  final record = <String, Object?>{
    ..._runtimeMap(mutation['record']),
  };
  if (_runtimeString(record['id']) == null) {
    record['id'] = _runtimeString(mutation['record_id']);
  }
  if (_runtimeString(record['title']) == null) {
    record['title'] = _runtimeString(mutation['title']);
  }
  await _storeRuntimeRecurringReminderRule(
    record,
    backend: backend,
    sessionKey: sessionKey,
    sourceMessageId: sourceMessageId ??
        _runtimeString(record['source_message_id']) ??
        _runtimeString(record['sourceMessageId']) ??
        _runtimeString(mutation['source_message_id']) ??
        _runtimeString(mutation['sourceMessageId']),
  );
}

Future<void> _storeRuntimeRecurringReminderRule(
  Map<String, Object?> record, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  final ruleId = _runtimeRecurringReminderRuleId(record);
  final title = _runtimeRecurringReminderTitle(record);
  final dueAtMs = _runtimeNextFireAtMs(record);
  final recurrenceRuleJson = _runtimeRecurrenceRuleJson(record);
  if (ruleId == null ||
      title == null ||
      dueAtMs == null ||
      recurrenceRuleJson == null) {
    return;
  }

  final todoId = _firstRuntimeString([
        record['todo_id'],
        record['todoId'],
        record['task_id'],
        record['taskId'],
        record['reminder_id'],
        record['reminderId'],
      ]) ??
      'todo:$ruleId';
  final seriesId = _firstRuntimeString([
        record['series_id'],
        record['seriesId'],
      ]) ??
      'series:$ruleId';
  await backend.upsertTodo(
    sessionKey,
    id: todoId,
    title: title,
    dueAtMs: dueAtMs,
    status: runtimeTodoStatusOrNull(record['todo_status']) ??
        runtimeTodoStatusOrNull(record['todoStatus']) ??
        runtimeTodoStatusOrNull(record['task_status']) ??
        runtimeTodoStatusOrNull(record['taskStatus']) ??
        'open',
    sourceEntryId: sourceMessageId,
  );
  await backend.upsertTodoRecurrence(
    sessionKey,
    todoId: todoId,
    seriesId: seriesId,
    ruleJson: recurrenceRuleJson,
  );
}

bool _isRuntimeRecurringReminderEntity(String? entityType) {
  return entityType == 'recurring_reminder_rule' ||
      entityType == 'recurring_reminder';
}

String? _runtimeRecurringReminderRuleId(Map<String, Object?> record) {
  return _firstRuntimeString([
    record['id'],
    record['rule_id'],
    record['ruleId'],
    record['recurring_rule_id'],
    record['recurringRuleId'],
  ]);
}

String? _runtimeRecurringReminderTitle(Map<String, Object?> record) {
  return _firstRuntimeString([
    record['title'],
    record['label'],
    record['summary'],
    record['text'],
    record['content'],
    record['body'],
  ]);
}

int? _runtimeNextFireAtMs(Map<String, Object?> record) {
  return _runtimeInt(record['next_fire_at_ms']) ??
      _runtimeInt(record['nextFireAtMs']) ??
      _runtimeInt(record['fire_at_ms']) ??
      _runtimeInt(record['fireAtMs']) ??
      _runtimeInt(record['remind_at_ms']) ??
      _runtimeInt(record['remindAtMs']) ??
      _runtimeDueAtMs(record) ??
      _runtimeIsoDateTimeMs(record['next_fire_at']) ??
      _runtimeIsoDateTimeMs(record['nextFireAt']) ??
      _runtimeIsoDateTimeMs(record['fire_at']) ??
      _runtimeIsoDateTimeMs(record['fireAt']);
}

String? _runtimeRecurrenceRuleJson(Map<String, Object?> record) {
  final explicit = _runtimeString(record['recurrence_rule_json']) ??
      _runtimeString(record['recurrenceRuleJson']) ??
      _runtimeString(record['rule_json']) ??
      _runtimeString(record['ruleJson']);
  if (explicit != null) {
    final normalized = _runtimeRecurrenceRuleJsonFromMap(
      _runtimeJsonObjectMap(explicit),
    );
    if (normalized != null) return normalized;
  }

  final explicitMap = _runtimeMap(record['recurrence_rule']);
  final normalizedExplicitMap = _runtimeRecurrenceRuleJsonFromMap(explicitMap);
  if (normalizedExplicitMap != null) return normalizedExplicitMap;

  final explicitCamelMap = _runtimeMap(record['recurrenceRule']);
  final normalizedExplicitCamelMap =
      _runtimeRecurrenceRuleJsonFromMap(explicitCamelMap);
  if (normalizedExplicitCamelMap != null) return normalizedExplicitCamelMap;

  final schedule = _runtimeMap(record['schedule']);
  final freq =
      _runtimeRecurrenceFreq(schedule) ?? _runtimeRecurrenceFreq(record);
  if (freq == null) return null;
  return jsonEncode(<String, Object?>{
    'freq': freq,
    'interval': _runtimeRecurrenceInterval(schedule, fallback: record),
  });
}

String? _runtimeRecurrenceRuleJsonFromMap(Map<String, Object?> source) {
  if (source.isEmpty) return null;
  final freq = _runtimeRecurrenceFreq(source);
  if (freq == null) return null;
  return jsonEncode(<String, Object?>{
    'freq': freq,
    'interval': _runtimeRecurrenceInterval(source),
  });
}

String? _runtimeRecurrenceFreq(Map<String, Object?> source) {
  final raw = _firstRuntimeString([
    source['freq'],
    source['frequency'],
    source['type'],
    source['cadence'],
  ])?.toLowerCase();
  if (raw == null) return null;
  if (raw.contains('year')) return 'yearly';
  if (raw.contains('quarter')) return 'monthly';
  if (raw.contains('month')) return 'monthly';
  if (raw.contains('week')) return 'weekly';
  if (raw.contains('day')) return 'daily';
  return null;
}

int _runtimeRecurrenceInterval(
  Map<String, Object?> source, {
  Map<String, Object?> fallback = const <String, Object?>{},
}) {
  final raw = _runtimeInt(source['interval']) ??
      _runtimeInt(source['every']) ??
      _runtimeInt(source['every_n']) ??
      _runtimeInt(source['everyN']) ??
      _runtimeInt(source['interval_months']) ??
      _runtimeInt(source['intervalMonths']) ??
      _runtimeInt(fallback['interval']) ??
      _runtimeInt(fallback['every']) ??
      _runtimeInt(fallback['every_n']) ??
      _runtimeInt(fallback['everyN']);
  if (raw != null && raw > 0) return raw;
  final type = _runtimeString(source['type'])?.toLowerCase() ?? '';
  if (type.contains('quarter')) return 3;
  return 1;
}

Map<String, Object?> _runtimeJsonObjectMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return _runtimeMap(decoded);
  } on FormatException {
    return const <String, Object?>{};
  }
}

String? _webResearchCitationsJson(
  SecretaryRuntimeConversationResult result,
) {
  final sources = <Map<String, Object?>>[];
  final seenHrefs = <String>{};

  for (final draft in result.metadata.webResearchDrafts) {
    final rawCitations = draft['citations'];
    if (rawCitations is! List) continue;
    for (final rawCitation in rawCitations) {
      final citation = _runtimeMap(rawCitation);
      final href = _firstRuntimeString([
        citation['href'],
        citation['url'],
        citation['source_url'],
        citation['sourceUrl'],
      ]);
      if (href == null || !_isHttpUrl(href)) continue;
      if (!seenHrefs.add(href)) continue;

      final title = _firstRuntimeString([
        citation['title'],
        citation['name'],
        citation['domain'],
        draft['query'],
      ]);
      final snippet = _firstRuntimeString([
            citation['snippet'],
            citation['summary'],
            citation['description'],
            draft['summary'],
          ]) ??
          '';
      final fetchedAtMs = _firstRuntimeInt([
        citation['fetched_at_ms'],
        citation['fetchedAtMs'],
        citation['created_at_ms'],
        citation['createdAtMs'],
        draft['fetched_at_ms'],
        draft['created_at_ms'],
      ]);
      final domain = _firstRuntimeString([
        citation['domain'],
        citation['site_name'],
        citation['siteName'],
      ]);

      sources.add(<String, Object?>{
        'id': 'web_research:${sources.length + 1}',
        'href': href,
        'source_type': 'web_research',
        'label': domain ?? 'Web',
        'source_type_label': 'Web research',
        'scope_label': 'Runtime web research',
        'confidence_label': 'Cited source',
        if (title != null) 'title': title,
        'snippet': snippet,
        if (fetchedAtMs != null) 'created_at_ms': fetchedAtMs,
        if (fetchedAtMs != null) 'updated_at_ms': fetchedAtMs,
      });
    }
  }

  if (sources.isEmpty) return null;
  return jsonEncode(<String, Object?>{'direct_sources': sources});
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

String? _firstRuntimeString(Iterable<Object?> values) {
  for (final value in values) {
    final text = _runtimeString(value);
    if (text != null) return text;
  }
  return null;
}

int? _firstRuntimeInt(Iterable<Object?> values) {
  for (final value in values) {
    final integer = _runtimeInt(value);
    if (integer != null) return integer;
  }
  return null;
}

Map<String, Object?> _runtimeMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

String? _runtimeString(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _runtimeDueAtMs(
  Map<String, Object?> record, {
  Map<String, Object?> fallback = const <String, Object?>{},
}) {
  return _runtimeInt(record['due_at_ms']) ??
      _runtimeInt(record['dueAtMs']) ??
      _runtimeInt(record['new_due_at_ms']) ??
      _runtimeInt(record['newDueAtMs']) ??
      _runtimeInt(fallback['due_at_ms']) ??
      _runtimeInt(fallback['dueAtMs']) ??
      _runtimeIsoDateTimeMs(record['due_local_iso']) ??
      _runtimeIsoDateTimeMs(record['dueLocalIso']) ??
      _runtimeTodayTimeMs(record['due_time']) ??
      _runtimeTodayTimeMs(record['dueTime']) ??
      _runtimeTodayTimeMs(record['new_due_time']) ??
      _runtimeTodayTimeMs(record['newDueTime']);
}

int? _runtimeIsoDateTimeMs(Object? raw) {
  final value = _runtimeString(raw);
  if (value == null) return null;
  return DateTime.tryParse(value)?.millisecondsSinceEpoch;
}

int? _runtimeTodayTimeMs(Object? raw) {
  final value = _runtimeString(raw);
  if (value == null) return null;
  final match =
      RegExp(r'([01]?\d|2[0-3])\s*[:：]\s*([0-5]\d)').firstMatch(value);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
}

int? _runtimeInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

double? _runtimeDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

bool _runtimeBool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is String) return raw.toLowerCase() == 'true';
  return false;
}
