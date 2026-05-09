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
  });

  final String runId;
  final String turnId;
  final String conversationId;
  final String vaultId;
  final String responseType;
  final String runStatus;
  final bool approvalRequired;
  final List<Map<String, Object?>> proposedMutations;
  final List<Map<String, Object?>> appliedMutations;
  final List<SecretaryRuntimeApprovalItem> approvalItems;

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
      proposedMutations: _parseObjectList(json['proposed_mutations']),
      appliedMutations: _parseObjectList(json['applied_mutations']),
      approvalItems: _parseApprovalItems(json['approval_items']),
    );
  }
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
