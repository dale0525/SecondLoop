import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
final class RuntimeAgentState {
  const RuntimeAgentState({
    required this.vaultId,
    required this.conversationId,
    required this.conversationTurns,
    required this.workingSetRecords,
    required this.tasks,
    required this.memoryRecords,
    required this.recurringReminderRules,
    required this.approvalItems,
    required this.recentEntityRefs,
    required this.latestContextSnapshot,
    required this.auditRefs,
  });

  final String vaultId;
  final String conversationId;
  final List<RuntimeConversationTurn> conversationTurns;
  final List<RuntimeWorkingSetRecord> workingSetRecords;
  final List<RuntimeWorkingSetRecord> tasks;
  final List<RuntimeWorkingSetRecord> memoryRecords;
  final List<Map<String, Object?>> recurringReminderRules;
  final List<Map<String, Object?>> approvalItems;
  final List<Map<String, Object?>> recentEntityRefs;
  final RuntimeContextSnapshot? latestContextSnapshot;
  final List<Map<String, Object?>> auditRefs;

  factory RuntimeAgentState.empty({
    String vaultId = '',
    String conversationId = '',
  }) {
    return RuntimeAgentState(
      vaultId: vaultId,
      conversationId: conversationId,
      conversationTurns: const <RuntimeConversationTurn>[],
      workingSetRecords: const <RuntimeWorkingSetRecord>[],
      tasks: const <RuntimeWorkingSetRecord>[],
      memoryRecords: const <RuntimeWorkingSetRecord>[],
      recurringReminderRules: const <Map<String, Object?>>[],
      approvalItems: const <Map<String, Object?>>[],
      recentEntityRefs: const <Map<String, Object?>>[],
      latestContextSnapshot: null,
      auditRefs: const <Map<String, Object?>>[],
    );
  }

  factory RuntimeAgentState.fromJson(Map<String, dynamic> json) {
    return RuntimeAgentState(
      vaultId: _parseString(json['vault_id']) ?? '',
      conversationId: _parseString(json['conversation_id']) ?? '',
      conversationTurns: _parseObjectList(json['conversation_turns'])
          .map(RuntimeConversationTurn.fromJson)
          .toList(growable: false),
      workingSetRecords: _parseObjectList(json['working_set_records'])
          .map(RuntimeWorkingSetRecord.fromJson)
          .toList(growable: false),
      tasks: _parseObjectList(json['tasks'])
          .map(RuntimeWorkingSetRecord.fromJson)
          .toList(growable: false),
      memoryRecords: _parseObjectList(json['memory_records'])
          .map(RuntimeWorkingSetRecord.fromJson)
          .toList(growable: false),
      recurringReminderRules: _parseObjectList(
        json['recurring_reminder_rules'],
      ),
      approvalItems: _parseObjectList(json['approval_items']),
      recentEntityRefs: _parseObjectList(json['recent_entity_refs']),
      latestContextSnapshot: _parseContextSnapshot(
        json['latest_context_snapshot'],
      ),
      auditRefs: _parseObjectList(json['audit_refs']),
    );
  }
}

@immutable
final class RuntimeConversationTurn {
  const RuntimeConversationTurn({
    required this.turnId,
    required this.conversationId,
    required this.vaultId,
    required this.role,
    required this.content,
    required this.attachmentRefs,
    required this.citationsJson,
    required this.createdAtMs,
    required this.raw,
  });

  final String turnId;
  final String conversationId;
  final String vaultId;
  final String role;
  final String content;
  final List<String> attachmentRefs;
  final String? citationsJson;
  final int createdAtMs;
  final Map<String, Object?> raw;

  factory RuntimeConversationTurn.fromJson(Map<String, Object?> json) {
    final webResearchDrafts = _parseObjectList(json['web_research_drafts']);
    return RuntimeConversationTurn(
      turnId: _parseString(json['turn_id']) ?? '',
      conversationId: _parseString(json['conversation_id']) ?? '',
      vaultId: _parseString(json['vault_id']) ?? '',
      role: _parseString(json['role']) ?? '',
      content: _parseString(json['content']) ?? '',
      attachmentRefs: _parseStringList(json['attachment_refs']),
      citationsJson: _parseString(json['citations_json']) ??
          _webResearchCitationsJson(webResearchDrafts),
      createdAtMs: _parseInt(json['created_at_ms']) ?? 0,
      raw: json,
    );
  }
}

@immutable
final class RuntimeWorkingSetRecord {
  const RuntimeWorkingSetRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.text,
    required this.summary,
    required this.body,
    required this.status,
    required this.updatedAtMs,
    required this.raw,
  });

  final String id;
  final String kind;
  final String title;
  final String text;
  final String summary;
  final String body;
  final String status;
  final int updatedAtMs;
  final Map<String, Object?> raw;

  factory RuntimeWorkingSetRecord.fromJson(Map<String, Object?> json) {
    final title = _firstString([
      json['title'],
      json['text'],
      json['content'],
      json['summary'],
      json['body'],
    ]);
    return RuntimeWorkingSetRecord(
      id: _firstString([json['id'], json['record_id']]) ?? '',
      kind: _parseString(json['kind']) ?? '',
      title: title ?? '',
      text: _parseString(json['text']) ?? '',
      summary: _parseString(json['summary']) ?? '',
      body: _parseString(json['body']) ?? '',
      status: _parseString(json['status']) ?? '',
      updatedAtMs: _parseInt(json['updated_at_ms']) ??
          _parseInt(json['updatedAtMs']) ??
          _parseInt(json['created_at_ms']) ??
          _parseInt(json['createdAtMs']) ??
          0,
      raw: json,
    );
  }
}

@immutable
final class RuntimeContextSnapshot {
  const RuntimeContextSnapshot({
    required this.id,
    required this.generatedAtMs,
    required this.packet,
    required this.raw,
  });

  final String id;
  final int generatedAtMs;
  final Map<String, Object?> packet;
  final Map<String, Object?> raw;

  factory RuntimeContextSnapshot.fromJson(Map<String, Object?> json) {
    return RuntimeContextSnapshot(
      id: _parseString(json['id']) ?? '',
      generatedAtMs: _parseInt(json['generated_at_ms']) ?? 0,
      packet: _parseObjectMap(json['packet']),
      raw: json,
    );
  }
}

RuntimeContextSnapshot? _parseContextSnapshot(Object? raw) {
  if (raw is! Map) return null;
  return RuntimeContextSnapshot.fromJson(
    raw.map((key, value) => MapEntry('$key', value as Object?)),
  );
}

List<Map<String, Object?>> _parseObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((item) =>
          item.map((key, value) => MapEntry('$key', value as Object?)))
      .toList(growable: false);
}

Map<String, Object?> _parseObjectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

List<String> _parseStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.map((item) => '$item').toList(growable: false);
}

String? _firstString(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = _parseString(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _parseString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _webResearchCitationsJson(List<Map<String, Object?>> drafts) {
  final sources = <Map<String, Object?>>[];
  final seenHrefs = <String>{};
  for (final draft in drafts) {
    final citations = _parseObjectList(draft['citations']);
    for (final citation in citations) {
      final href = _firstString([
        citation['href'],
        citation['url'],
        citation['source_url'],
        citation['sourceUrl'],
      ]);
      if (href == null || !_isHttpUrl(href)) continue;
      if (!seenHrefs.add(href)) continue;

      final title = _firstString([
        citation['title'],
        citation['name'],
        citation['domain'],
        draft['query'],
      ]);
      final snippet = _firstString([
            citation['snippet'],
            citation['summary'],
            citation['description'],
            draft['summary'],
          ]) ??
          '';
      final fetchedAtMs = _firstInt([
        citation['fetched_at_ms'],
        citation['fetchedAtMs'],
        citation['created_at_ms'],
        citation['createdAtMs'],
        draft['fetched_at_ms'],
        draft['created_at_ms'],
      ]);
      final domain = _firstString([
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

int? _firstInt(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = _parseInt(value);
    if (parsed != null) return parsed;
  }
  return null;
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
