part of 'native_backend.dart';

String _dartSecretaryMemoryStoreKey(Uint8List key) {
  return 'secretary_memory_store_json_v1:${base64Url.encode(key)}';
}

String _sourceDocumentIdsJson(String? sourceMessageId) {
  final normalized = sourceMessageId?.trim();
  if (normalized == null || normalized.isEmpty) return '[]';
  return jsonEncode(<String>[normalized]);
}

SecretaryMemoryProposalRecord _copyProposal(
  SecretaryMemoryProposalRecord proposal, {
  String? state,
  int? updatedAtMs,
  int? acceptedAtMs,
  int? dismissedAtMs,
}) {
  return SecretaryMemoryProposalRecord(
    id: proposal.id,
    sourceMessageId: proposal.sourceMessageId,
    kind: proposal.kind,
    title: proposal.title,
    body: proposal.body,
    confidence: proposal.confidence,
    state: state ?? proposal.state,
    sourceRefsJson: proposal.sourceRefsJson,
    actionHint: proposal.actionHint,
    createdAtMs: proposal.createdAtMs,
    updatedAtMs: platformIntFromInt(
      updatedAtMs ?? platformIntToInt(proposal.updatedAtMs),
    ),
    acceptedAtMs: acceptedAtMs == null
        ? proposal.acceptedAtMs
        : platformIntFromInt(acceptedAtMs),
    dismissedAtMs: dismissedAtMs == null
        ? proposal.dismissedAtMs
        : platformIntFromInt(dismissedAtMs),
  );
}

MemoryPageRecord _copyPage(
  MemoryPageRecord page, {
  String? state,
  String? title,
  String? summary,
  String? body,
  bool? humanCorrected,
  int? updatedAtMs,
}) {
  return MemoryPageRecord(
    pageId: page.pageId,
    pageType: page.pageType,
    state: state ?? page.state,
    sourceCount: page.sourceCount,
    title: title ?? page.title,
    summary: summary ?? page.summary,
    body: body ?? page.body,
    primaryEvidenceJson: page.primaryEvidenceJson,
    sourceDocumentIdsJson: page.sourceDocumentIdsJson,
    confidenceLevel: page.confidenceLevel,
    humanCorrected: humanCorrected ?? page.humanCorrected,
    createdAtMs: page.createdAtMs,
    updatedAtMs: platformIntFromInt(
      updatedAtMs ?? platformIntToInt(page.updatedAtMs),
    ),
  );
}

final class _DartSecretaryMemoryStore {
  const _DartSecretaryMemoryStore({
    required this.nextProposalSeq,
    required this.nextPageSeq,
    required this.proposals,
    required this.pages,
  });

  factory _DartSecretaryMemoryStore.empty() {
    return const _DartSecretaryMemoryStore(
      nextProposalSeq: 1,
      nextPageSeq: 1,
      proposals: <String, SecretaryMemoryProposalRecord>{},
      pages: <String, MemoryPageRecord>{},
    );
  }

  factory _DartSecretaryMemoryStore.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return _DartSecretaryMemoryStore.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _DartSecretaryMemoryStore.empty();
      final proposals = <String, SecretaryMemoryProposalRecord>{};
      final rawProposals = decoded['proposals'];
      if (rawProposals is List) {
        for (final item in rawProposals.whereType<Map>()) {
          final proposal = _proposalFromJson(item);
          if (proposal != null) proposals[proposal.id] = proposal;
        }
      }
      final pages = <String, MemoryPageRecord>{};
      final rawPages = decoded['pages'];
      if (rawPages is List) {
        for (final item in rawPages.whereType<Map>()) {
          final page = _pageFromJson(item);
          if (page != null) pages[page.pageId] = page;
        }
      }
      return _DartSecretaryMemoryStore(
        nextProposalSeq: _jsonInt(decoded['next_proposal_seq']) ??
            _nextSeqFromIds(proposals.keys, 'proposal-'),
        nextPageSeq: _jsonInt(decoded['next_page_seq']) ??
            _nextSeqFromIds(pages.keys, 'memory-'),
        proposals: proposals,
        pages: pages,
      );
    } catch (_) {
      return _DartSecretaryMemoryStore.empty();
    }
  }

  final int nextProposalSeq;
  final int nextPageSeq;
  final Map<String, SecretaryMemoryProposalRecord> proposals;
  final Map<String, MemoryPageRecord> pages;

  _DartSecretaryMemoryStore copyWith({
    int? nextProposalSeq,
    int? nextPageSeq,
    Map<String, SecretaryMemoryProposalRecord>? proposals,
    Map<String, MemoryPageRecord>? pages,
  }) {
    return _DartSecretaryMemoryStore(
      nextProposalSeq: nextProposalSeq ?? this.nextProposalSeq,
      nextPageSeq: nextPageSeq ?? this.nextPageSeq,
      proposals: proposals ?? this.proposals,
      pages: pages ?? this.pages,
    );
  }

  String toJsonString() {
    return jsonEncode(<String, Object?>{
      'next_proposal_seq': nextProposalSeq,
      'next_page_seq': nextPageSeq,
      'proposals': proposals.values.map(_proposalToJson).toList(),
      'pages': pages.values.map(_pageToJson).toList(),
    });
  }
}

SecretaryMemoryProposalRecord? _proposalFromJson(Map<dynamic, dynamic> json) {
  final id = _jsonString(json['id']);
  final kind = _jsonString(json['kind']);
  final title = _jsonString(json['title']);
  final body = _jsonString(json['body']);
  final state = _jsonString(json['state']);
  if (id == null ||
      kind == null ||
      title == null ||
      body == null ||
      state == null) {
    return null;
  }
  return SecretaryMemoryProposalRecord(
    id: id,
    sourceMessageId: _jsonString(json['source_message_id']),
    kind: kind,
    title: title,
    body: body,
    confidence: _jsonDouble(json['confidence']) ?? 0.0,
    state: state,
    sourceRefsJson: _jsonString(json['source_refs_json']),
    actionHint: _jsonString(json['action_hint']),
    createdAtMs: platformIntFromInt(_jsonInt(json['created_at_ms']) ?? 0),
    updatedAtMs: platformIntFromInt(_jsonInt(json['updated_at_ms']) ?? 0),
    acceptedAtMs: _jsonPlatformInt(json['accepted_at_ms']),
    dismissedAtMs: _jsonPlatformInt(json['dismissed_at_ms']),
  );
}

Map<String, Object?> _proposalToJson(SecretaryMemoryProposalRecord proposal) {
  return <String, Object?>{
    'id': proposal.id,
    'source_message_id': proposal.sourceMessageId,
    'kind': proposal.kind,
    'title': proposal.title,
    'body': proposal.body,
    'confidence': proposal.confidence,
    'state': proposal.state,
    'source_refs_json': proposal.sourceRefsJson,
    'action_hint': proposal.actionHint,
    'created_at_ms': platformIntToInt(proposal.createdAtMs),
    'updated_at_ms': platformIntToInt(proposal.updatedAtMs),
    'accepted_at_ms': platformIntToNullableInt(proposal.acceptedAtMs),
    'dismissed_at_ms': platformIntToNullableInt(proposal.dismissedAtMs),
  };
}

MemoryPageRecord? _pageFromJson(Map<dynamic, dynamic> json) {
  final pageId = _jsonString(json['page_id']);
  final title = _jsonString(json['title']);
  final summary = _jsonString(json['summary']);
  final body = _jsonString(json['body']);
  if (pageId == null || title == null || summary == null || body == null) {
    return null;
  }
  return MemoryPageRecord(
    pageId: pageId,
    pageType: _jsonString(json['page_type']) ?? 'memory',
    state: _jsonString(json['state']) ?? 'active',
    sourceCount: platformIntFromInt(_jsonInt(json['source_count']) ?? 0),
    title: title,
    summary: summary,
    body: body,
    primaryEvidenceJson: _jsonString(json['primary_evidence_json']) ?? '[]',
    sourceDocumentIdsJson:
        _jsonString(json['source_document_ids_json']) ?? '[]',
    confidenceLevel: _jsonDouble(json['confidence_level']) ?? 0.0,
    humanCorrected: json['human_corrected'] == true,
    createdAtMs: platformIntFromInt(_jsonInt(json['created_at_ms']) ?? 0),
    updatedAtMs: platformIntFromInt(_jsonInt(json['updated_at_ms']) ?? 0),
  );
}

Map<String, Object?> _pageToJson(MemoryPageRecord page) {
  return <String, Object?>{
    'page_id': page.pageId,
    'page_type': page.pageType,
    'state': page.state,
    'source_count': platformIntToInt(page.sourceCount),
    'title': page.title,
    'summary': page.summary,
    'body': page.body,
    'primary_evidence_json': page.primaryEvidenceJson,
    'source_document_ids_json': page.sourceDocumentIdsJson,
    'confidence_level': page.confidenceLevel,
    'human_corrected': page.humanCorrected,
    'created_at_ms': platformIntToInt(page.createdAtMs),
    'updated_at_ms': platformIntToInt(page.updatedAtMs),
  };
}

int _nextSeqFromIds(Iterable<String> ids, String prefix) {
  var next = 1;
  for (final id in ids) {
    if (!id.startsWith(prefix)) continue;
    final value = int.tryParse(id.substring(prefix.length));
    if (value != null && value >= next) next = value + 1;
  }
  return next;
}

String? _jsonString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _jsonInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _jsonDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

PlatformInt64? _jsonPlatformInt(Object? value) {
  final parsed = _jsonInt(value);
  return parsed == null ? null : platformIntFromInt(parsed);
}
