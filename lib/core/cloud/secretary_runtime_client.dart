import 'package:flutter/foundation.dart';

import 'runtime_api_client.dart';
import 'secretary_runtime_conversation_models.dart';

@immutable
class SecretaryRuntimePlanItem {
  const SecretaryRuntimePlanItem({
    required this.id,
    required this.taskId,
    required this.title,
    required this.status,
    required this.requiresConfirmation,
  });

  final String id;
  final String taskId;
  final String title;
  final String status;
  final bool requiresConfirmation;

  factory SecretaryRuntimePlanItem.fromJson(Map<String, dynamic> json) {
    return SecretaryRuntimePlanItem(
      id: (json['id'] as String?) ?? '',
      taskId: (json['task_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'open',
      requiresConfirmation: json['requires_confirmation'] == true,
    );
  }
}

@immutable
class SecretaryRuntimePlanDraft {
  const SecretaryRuntimePlanDraft({
    required this.id,
    required this.title,
    required this.generatedAtMs,
    required this.items,
  });

  final String id;
  final String title;
  final int generatedAtMs;
  final List<SecretaryRuntimePlanItem> items;

  factory SecretaryRuntimePlanDraft.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SecretaryRuntimePlanDraft(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      generatedAtMs: (json['generated_at_ms'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) => SecretaryRuntimePlanItem.fromJson(
                  item.map((key, value) => MapEntry('$key', value)),
                ),
              )
              .toList(growable: false)
          : const <SecretaryRuntimePlanItem>[],
    );
  }
}

@immutable
class SecretaryRuntimeApprovalItem {
  const SecretaryRuntimeApprovalItem({
    required this.id,
    required this.taskId,
    required this.title,
    required this.kind,
    this.recurringRuleId = '',
    this.emailDraftId = '',
    this.calendarEventId = '',
    this.reason = '',
    this.record,
  });

  final String id;
  final String taskId;
  final String title;
  final String kind;
  final String recurringRuleId;
  final String emailDraftId;
  final String calendarEventId;
  final String reason;
  final Map<String, Object?>? record;

  factory SecretaryRuntimeApprovalItem.fromJson(Map<String, dynamic> json) {
    return SecretaryRuntimeApprovalItem(
      id: (json['id'] as String?) ?? '',
      taskId: (json['task_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? '',
      recurringRuleId: (json['recurring_rule_id'] as String?) ?? '',
      emailDraftId: (json['email_draft_id'] as String?) ?? '',
      calendarEventId: (json['calendar_event_id'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      record: _parseNullableObjectMap(json['record']),
    );
  }
}

Map<String, Object?>? _parseNullableObjectMap(Object? raw) {
  if (raw == null || raw is! Map) {
    return null;
  }
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

final class SecretaryRuntimeClient {
  SecretaryRuntimeClient({
    RuntimeApiClient? apiClient,
  }) : _apiClient = apiClient ?? RuntimeApiClient();

  final RuntimeApiClient _apiClient;

  Future<List<SecretaryRuntimePlanDraft>> fetchPlans(String vaultId) async {
    final response =
        await _apiClient.getJson('/v1/runtime/vaults/$vaultId/plans');
    final rawItems = response?['items'];
    if (rawItems is! List) {
      return const <SecretaryRuntimePlanDraft>[];
    }
    return rawItems
        .whereType<Map>()
        .map(
          (item) => SecretaryRuntimePlanDraft.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
  }

  Future<SecretaryRuntimePlanDraft> requestPlanRefresh(
    String vaultId, {
    String runtimeMode = 'self_managed',
    String provider = 'openai',
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime/vaults/$vaultId/plans/generate',
      body: <String, Object?>{
        'runtime_mode': runtimeMode,
        'provider': provider,
      },
    );
    return SecretaryRuntimePlanDraft.fromJson(
      Map<String, dynamic>.from(response?['plan'] as Map? ?? const {}),
    );
  }

  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals(
      String vaultId) async {
    final response =
        await _apiClient.getJson('/v1/runtime/vaults/$vaultId/approvals');
    final rawItems = response?['items'];
    if (rawItems is! List) {
      return const <SecretaryRuntimeApprovalItem>[];
    }
    return rawItems
        .whereType<Map>()
        .map(
          (item) => SecretaryRuntimeApprovalItem.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
  }

  Future<String> createConversation(String vaultId) async {
    final response = await _apiClient.postJson(
      '/v1/runtime/vaults/$vaultId/conversations',
      body: const <String, Object?>{},
    );
    return (response?['conversation_id'] as String?) ?? '';
  }

  Future<SecretaryRuntimeConversationResult> sendConversationMessage(
    String vaultId, {
    required String conversationId,
    required String message,
    List<Map<String, Object?>> attachments = const [],
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime/vaults/$vaultId/conversations/$conversationId/messages',
      body: <String, Object?>{
        'message': message,
        'attachments': attachments,
      },
    );
    return SecretaryRuntimeConversationResult.fromJson(
      Map<String, dynamic>.from(response ?? const <String, dynamic>{}),
    );
  }

  Future<SecretaryRuntimeConversationResult> fetchRun(
    String vaultId, {
    required String runId,
  }) async {
    final response =
        await _apiClient.getJson('/v1/runtime/vaults/$vaultId/runs/$runId');
    return SecretaryRuntimeConversationResult.fromJson(
      Map<String, dynamic>.from(response ?? const <String, dynamic>{}),
    );
  }

  Future<void> submitApprovalDecision(
    String vaultId, {
    required String approvalId,
    required String decision,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime/vaults/$vaultId/approvals/decision',
      body: <String, Object?>{
        'approval_id': approvalId,
        'decision': decision,
      },
    );
  }

  Future<List<String>> fetchRuntimeCapabilities() async {
    final response = await _apiClient.getJson('/v1/runtime/capabilities');
    final rawItems = response?['capabilities'];
    if (rawItems is! List) {
      return const <String>[];
    }
    return rawItems.map((item) => '$item').toList(growable: false);
  }

  void dispose() {
    _apiClient.dispose();
  }
}
