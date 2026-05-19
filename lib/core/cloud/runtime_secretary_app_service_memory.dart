part of 'runtime_secretary_app_service.dart';

Future<void> applyRuntimeMemoryMutations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  if (backend is! SecretaryBackend) return;
  final secretaryBackend = backend as SecretaryBackend;
  for (final mutation in result.metadata.appliedMutations) {
    await _applyRuntimeMemoryMutation(
      mutation,
      backend: secretaryBackend,
      sessionKey: sessionKey,
      sourceMessageId: sourceMessageId,
    );
  }
}

bool _hasAppliedMemoryMutation(SecretaryRuntimeConversationResult result) {
  return result.metadata.appliedMutations.any((mutation) {
    final entityType = _runtimeString(mutation['entity_type']);
    return _isRuntimeMemoryEntity(entityType) &&
        _runtimeString(mutation['status']) == 'applied';
  });
}

Future<void> _applyRuntimeMemoryMutation(
  Map<String, Object?> mutation, {
  required SecretaryBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {
  if (!_isRuntimeMemoryEntity(_runtimeString(mutation['entity_type']))) return;
  if (_runtimeString(mutation['status']) != 'applied') return;
  final record = _runtimeMap(mutation['record']);
  final title = _runtimeMemoryTitle(
    record,
    fallback: _runtimeString(mutation['title']),
  );
  if (title == null) return;
  final body = _runtimeMemoryBody(
        record,
        fallback: _runtimeString(mutation['body']) ?? title,
      ) ??
      title;
  await _storeRuntimeMemoryCandidate(
    backend,
    sessionKey,
    title: title,
    body: body,
    kind: _runtimeMemoryKind(record),
    confidence: _runtimeDouble(record['confidence']) ??
        _runtimeDouble(mutation['confidence']) ??
        0.9,
    sourceMessageId: sourceMessageId ??
        _runtimeString(record['source_message_id']) ??
        _runtimeString(record['sourceMessageId']) ??
        _runtimeString(mutation['source_message_id']) ??
        _runtimeString(mutation['sourceMessageId']),
    sourceRefsJson: _runtimeMemorySourceRefsJson(record),
  );
}

Future<void> _storeRuntimeMemoryCandidate(
  SecretaryBackend backend,
  Uint8List sessionKey, {
  required String title,
  required String body,
  required String kind,
  required double confidence,
  String? sourceMessageId,
  String? sourceRefsJson,
}) async {
  final normalizedTitle = title.trim();
  final normalizedBody = body.trim();
  if (normalizedTitle.isEmpty || normalizedBody.isEmpty) return;
  if (await _hasMatchingActiveMemory(
    backend,
    sessionKey,
    title: normalizedTitle,
    body: normalizedBody,
  )) {
    return;
  }
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final proposal = await backend.createSecretaryMemoryProposal(
    sessionKey,
    sourceMessageId:
        sourceMessageId?.trim().isEmpty == true ? null : sourceMessageId,
    kind: kind,
    title: normalizedTitle,
    body: normalizedBody,
    confidence: confidence.clamp(0.0, 1.0).toDouble(),
    sourceRefsJson: sourceRefsJson,
    actionHint: 'runtime_memory_confirmation',
    nowMs: nowMs,
  );
  await backend.acceptSecretaryMemoryProposal(
    sessionKey,
    proposalId: proposal.id,
    nowMs: nowMs,
  );
}

Future<bool> _hasMatchingActiveMemory(
  SecretaryBackend backend,
  Uint8List sessionKey, {
  required String title,
  required String body,
}) async {
  final pages = await backend.listMemoryPages(sessionKey, state: 'active');
  return pages.any((page) {
    return page.title.trim() == title && page.body.trim() == body;
  });
}

bool _isRuntimeMemoryEntity(String? entityType) {
  return entityType == 'memory' ||
      entityType == 'memory_page' ||
      entityType == 'long_term_memory' ||
      entityType == 'user_memory' ||
      entityType == 'preference' ||
      entityType == 'knowledge_page';
}

String? _runtimeMemoryTitle(
  Map<String, Object?> record, {
  String? fallback,
}) {
  return _firstRuntimeString([
    record['title'],
    record['text'],
    record['content'],
    record['summary'],
    fallback,
  ]);
}

String? _runtimeMemoryBody(
  Map<String, Object?> record, {
  String? fallback,
}) {
  return _firstRuntimeString([
    record['body'],
    record['summary'],
    record['detail'],
    record['description'],
    record['text'],
    record['content'],
    fallback,
  ]);
}

String _runtimeMemoryKind(Map<String, Object?> record) {
  return _firstRuntimeString([
        record['kind'],
        record['memory_kind'],
        record['memoryKind'],
        record['page_type'],
        record['pageType'],
      ]) ??
      'preference';
}

String? _runtimeMemorySourceRefsJson(
  Map<String, Object?> record, {
  String? approvalId,
}) {
  final explicit = _runtimeString(record['source_refs_json']) ??
      _runtimeString(record['sourceRefsJson']);
  if (explicit != null) return explicit;
  final refs = <String, Object?>{
    if (approvalId != null && approvalId.trim().isNotEmpty)
      'approval_id': approvalId,
    if (_runtimeString(record['id']) != null) 'record_id': record['id'],
  };
  return refs.isEmpty ? null : jsonEncode(refs);
}
