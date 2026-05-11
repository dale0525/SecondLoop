import 'dart:typed_data';

import '../backend/app_backend.dart';
import 'secretary_runtime_conversation_models.dart';
import 'secretary_runtime_conversation_sender.dart';

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
      await _backend.insertMessage(
        _sessionKey,
        conversationId,
        role: 'assistant',
        content: content,
      );
    }
    await applyRuntimeTaskCreations(
      result,
      backend: _backend,
      sessionKey: _sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }
}

Future<void> applyRuntimeTaskCreations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  for (final mutation in result.metadata.appliedMutations) {
    if (_runtimeString(mutation['entity_type']) != 'task') continue;
    if (_runtimeString(mutation['mutation_type']) != 'create') continue;
    if (_runtimeString(mutation['status']) != 'applied') continue;

    final record = _runtimeMap(mutation['record']);
    final id = _runtimeString(record['id']) ??
        _runtimeString(record['task_id']) ??
        _runtimeString(mutation['record_id']);
    final title = _runtimeString(record['title']);
    if (id == null || title == null) continue;

    await backend.upsertTodo(
      sessionKey,
      id: id,
      title: title,
      dueAtMs:
          _runtimeInt(record['due_at_ms']) ?? _runtimeInt(record['dueAtMs']),
      status: runtimeTodoStatus(record['status']),
      sourceEntryId: sourceMessageId,
      reviewStage: _runtimeInt(record['review_stage']) ??
          _runtimeInt(record['reviewStage']),
      nextReviewAtMs: _runtimeInt(record['next_review_at_ms']) ??
          _runtimeInt(record['nextReviewAtMs']),
      lastReviewAtMs: _runtimeInt(record['last_review_at_ms']) ??
          _runtimeInt(record['lastReviewAtMs']),
    );
  }
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

Map<String, Object?> _runtimeMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

String? _runtimeString(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _runtimeInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
