import 'package:flutter/foundation.dart';

import 'secretary_runtime_client.dart';

@immutable
final class SecretaryRuntimeConversationResult {
  const SecretaryRuntimeConversationResult({
    required this.runId,
    required this.conversationId,
    required this.assistantContent,
    required this.metadata,
  });

  final String runId;
  final String conversationId;
  final String assistantContent;
  final SecretaryRuntimeResponseMetadata metadata;

  factory SecretaryRuntimeConversationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final assistant = json['assistant'];
    final metadata = json['metadata'];
    return SecretaryRuntimeConversationResult(
      runId: _parseString(json['run_id']) ?? '',
      conversationId: _parseString(json['conversation_id']) ?? '',
      assistantContent:
          assistant is Map ? _parseString(assistant['content']) ?? '' : '',
      metadata: SecretaryRuntimeResponseMetadata.fromJson(
        metadata is Map
            ? metadata.map((key, value) => MapEntry('$key', value))
            : const <String, dynamic>{},
      ),
    );
  }
}

@immutable
final class SecretaryRuntimeResponseMetadata {
  const SecretaryRuntimeResponseMetadata({
    required this.runId,
    required this.turnId,
    required this.conversationId,
    required this.vaultId,
    required this.responseType,
    required this.runStatus,
    required this.approvalRequired,
    required this.proposedMutations,
    required this.appliedMutations,
    required this.approvalItems,
    this.confidence,
    this.referencedEntities = const <String, Object?>{},
    this.draftEntities = const <Map<String, Object?>>[],
    this.toolTraceIds = const <String>[],
    this.providerTraceId,
    this.stateSnapshotAfter,
    this.requiresHighCostConfirmation = false,
  });

  final String runId;
  final String turnId;
  final String conversationId;
  final String vaultId;
  final String responseType;
  final String runStatus;
  final bool approvalRequired;
  final double? confidence;
  final Map<String, Object?> referencedEntities;
  final List<Map<String, Object?>> proposedMutations;
  final List<Map<String, Object?>> appliedMutations;
  final List<Map<String, Object?>> draftEntities;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
  final List<String> toolTraceIds;
  final String? providerTraceId;
  final Map<String, Object?>? stateSnapshotAfter;
  final bool requiresHighCostConfirmation;

  factory SecretaryRuntimeResponseMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return SecretaryRuntimeResponseMetadata(
      runId: _parseString(json['run_id']) ?? '',
      turnId: _parseString(json['turn_id']) ?? '',
      conversationId: _parseString(json['conversation_id']) ?? '',
      vaultId: _parseString(json['vault_id']) ?? '',
      responseType: _parseString(json['response_type']) ?? '',
      runStatus: _parseString(json['run_status']) ?? '',
      approvalRequired: json['approval_required'] == true,
      confidence: _parseDouble(json['confidence']),
      referencedEntities: _parseObjectMap(json['referenced_entities']),
      proposedMutations: _parseObjectList(json['proposed_mutations']),
      appliedMutations: _parseObjectList(json['applied_mutations']),
      draftEntities: _parseObjectList(json['draft_entities']),
      approvalItems: _parseApprovalItems(json['approval_items']),
      toolTraceIds: _parseStringList(json['tool_trace_ids']),
      providerTraceId: _parseString(json['provider_trace_id']),
      stateSnapshotAfter: _parseNullableObjectMap(json['state_snapshot_after']),
      requiresHighCostConfirmation:
          json['requires_high_cost_confirmation'] == true,
    );
  }
}

double? _parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Map<String, Object?> _parseObjectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

Map<String, Object?>? _parseNullableObjectMap(Object? raw) {
  if (raw == null) return null;
  final parsed = _parseObjectMap(raw);
  return parsed.isEmpty && raw is! Map ? null : parsed;
}

List<Map<String, Object?>> _parseObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry('$key', value as Object?),
        ),
      )
      .toList(growable: false);
}

List<String> _parseStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.map((item) => '$item').toList(growable: false);
}

List<SecretaryRuntimeApprovalItem> _parseApprovalItems(Object? raw) {
  if (raw is! List) return const <SecretaryRuntimeApprovalItem>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => SecretaryRuntimeApprovalItem.fromJson(
          item.map((key, value) => MapEntry('$key', value)),
        ),
      )
      .toList(growable: false);
}

String? _parseString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
