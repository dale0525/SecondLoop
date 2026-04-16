import 'dart:convert';

import 'chat_answer_evidence_models.dart';

ChatAnswerEvidence? parseChatAnswerEvidence(String? citationsJson) {
  final raw = citationsJson?.trim();
  if (raw == null || raw.isEmpty) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final directSources = <ChatAnswerEvidenceDirectSource>[];

  final directRaw = decoded['direct_sources'];
  if (directRaw is List) {
    for (final item in directRaw) {
      final parsed = _parseDirectSource(item);
      if (parsed != null) {
        directSources.add(parsed);
      }
    }
  }

  final evidence = ChatAnswerEvidence(
    directSources: directSources,
    memoryCards: const <ChatAnswerEvidenceMemoryCard>[],
  );
  return evidence.hasEvidence ? evidence : null;
}

ChatAnswerEvidenceDirectSource? _parseDirectSource(Object? raw) {
  if (raw is! Map) return null;
  final id = _readString(raw['id']);
  final href = _readString(raw['href']);
  if (id == null || href == null) return null;
  return ChatAnswerEvidenceDirectSource(
    id: id,
    href: href,
    sourceType: _readString(raw['source_type']) ?? '',
    label: _readString(raw['label']) ?? '',
    sourceTypeLabel: _readString(raw['source_type_label']),
    scopeLabel: _readString(raw['scope_label']),
    confidenceLabel: _readString(raw['confidence_label']),
    title: _readString(raw['title']),
    snippet: _readString(raw['snippet']) ?? '',
    highlightedText: _readString(raw['highlighted_text']),
    createdAtMs: _readInt(raw['created_at_ms']),
    updatedAtMs: _readInt(raw['updated_at_ms']),
    documentId: _readString(raw['document_id']),
    unitId: _readString(raw['unit_id']),
  );
}

String? _readString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
