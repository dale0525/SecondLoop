import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import 'secretary_ai_prompts.dart';
import 'secretary_models.dart';

const String secretaryAiPurpose = 'secretary';

enum SecretaryAiRouteKind {
  localOnly,
  cloudGateway,
}

final class SecretaryAiRouteConfig {
  const SecretaryAiRouteConfig.localOnly()
      : kind = SecretaryAiRouteKind.localOnly,
        cloudGatewayBaseUrl = null,
        cloudIdToken = null,
        cloudModelName = null;

  const SecretaryAiRouteConfig.cloudGateway({
    required this.cloudGatewayBaseUrl,
    required this.cloudIdToken,
    required this.cloudModelName,
  }) : kind = SecretaryAiRouteKind.cloudGateway;

  final SecretaryAiRouteKind kind;
  final String? cloudGatewayBaseUrl;
  final String? cloudIdToken;
  final String? cloudModelName;

  bool get canCallAi => kind != SecretaryAiRouteKind.localOnly;

  String get wireRoute => switch (kind) {
        SecretaryAiRouteKind.localOnly => 'local_rules',
        SecretaryAiRouteKind.cloudGateway => 'cloud_gateway',
      };
}

abstract interface class SecretaryAiPromptClient {
  Future<String> runCloudSecretaryPrompt(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String purpose,
  });
}

final class BackendSecretaryAiPromptClient implements SecretaryAiPromptClient {
  BackendSecretaryAiPromptClient({
    http.Client Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final http.Client Function() _httpClientFactory;

  @override
  Future<String> runCloudSecretaryPrompt(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String purpose,
  }) async {
    final client = _httpClientFactory();
    try {
      final base = gatewayBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final response = await client.post(
        Uri.parse('$base/v1/chat/completions'),
        headers: {
          'authorization': 'Bearer $idToken',
          'accept': 'application/json',
          'content-type': 'application/json',
          'x-secondloop-purpose': purpose,
        },
        body: jsonEncode({
          'model': modelName,
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  'Return compact JSON only for SecondLoop secretary drafts.',
            },
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'secretary_cloud_http_${response.statusCode}: ${response.body}',
        );
      }
      return _openAiContentFromResponse(response.body);
    } finally {
      client.close();
    }
  }

  String _openAiContentFromResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return body;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return body;
    final first = choices.first;
    if (first is! Map) return body;
    final message = first['message'];
    if (message is! Map) return body;
    final content = message['content'];
    return content is String ? content : body;
  }
}

final class SecretaryAiService {
  const SecretaryAiService({required SecretaryAiPromptClient promptClient})
      : _promptClient = promptClient;

  final SecretaryAiPromptClient _promptClient;

  static Future<SecretaryAiRouteConfig> resolveRoute(
    AppBackend backend,
    Uint8List sessionKey, {
    required String? cloudIdToken,
    required String cloudGatewayBaseUrl,
    required String cloudModelName,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.unknown,
  }) async {
    final route = await decideAiAutomationRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayBaseUrl,
      subscriptionStatus: subscriptionStatus,
    );
    return switch (route) {
      AskAiRouteKind.cloudGateway => SecretaryAiRouteConfig.cloudGateway(
          cloudGatewayBaseUrl: cloudGatewayBaseUrl,
          cloudIdToken: cloudIdToken ?? '',
          cloudModelName: cloudModelName,
        ),
      AskAiRouteKind.needsSetup => const SecretaryAiRouteConfig.localOnly(),
    };
  }

  Future<SecretaryAiPlanningEnhancement> enhancePlan(
    Uint8List key, {
    required SecretaryPlan localPlan,
    required SecretaryAiRouteConfig routeConfig,
    required String localeTag,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!routeConfig.canCallAi) {
      return SecretaryAiPlanningEnhancement.empty(route: routeConfig.wireRoute);
    }
    final prompt = SecretaryAiPrompts.planningEnhancement(
      localPlan: localPlan,
      localeTag: localeTag,
    );
    final raw = await _runPrompt(
      key,
      prompt: prompt,
      routeConfig: routeConfig,
    ).timeout(timeout);
    return SecretaryAiPlanningEnhancement.fromJson(
      _decodeJsonObject(raw),
      route: routeConfig.wireRoute,
    );
  }

  Future<SecretaryAiPlanningEnhancement?> tryEnhancePlan(
    Uint8List key, {
    required SecretaryPlan localPlan,
    required SecretaryAiRouteConfig routeConfig,
    required String localeTag,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final enhancement = await enhancePlan(
        key,
        localPlan: localPlan,
        routeConfig: routeConfig,
        localeTag: localeTag,
        timeout: timeout,
      );
      return enhancement.isEmpty ? null : enhancement;
    } catch (_) {
      return null;
    }
  }

  Future<SecretaryAiMemoryProposalDraft> enhanceMemoryProposal(
    Uint8List key, {
    required SecretaryMemoryProposal proposal,
    required SecretaryAiRouteConfig routeConfig,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!routeConfig.canCallAi) {
      return SecretaryAiMemoryProposalDraft.fromProposal(proposal);
    }
    final prompt = SecretaryAiPrompts.memoryProposalEnhancement(
      proposal: proposal,
    );
    final raw = await _runPrompt(
      key,
      prompt: prompt,
      routeConfig: routeConfig,
    ).timeout(timeout);
    return SecretaryAiMemoryProposalDraft.fromJson(
      _decodeJsonObject(raw),
      fallback: proposal,
    );
  }

  Future<SecretaryAiMemoryProposalDraft?> tryEnhanceMemoryProposal(
    Uint8List key, {
    required SecretaryMemoryProposal proposal,
    required SecretaryAiRouteConfig routeConfig,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final draft = await enhanceMemoryProposal(
        key,
        proposal: proposal,
        routeConfig: routeConfig,
        timeout: timeout,
      );
      final changed = draft.kind != proposal.kind ||
          draft.title != proposal.title ||
          draft.body != proposal.body ||
          draft.confidence > proposal.confidence ||
          draft.supersedesCandidateIds.isNotEmpty;
      return changed ? draft : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _runPrompt(
    Uint8List key, {
    required String prompt,
    required SecretaryAiRouteConfig routeConfig,
  }) {
    return switch (routeConfig.kind) {
      SecretaryAiRouteKind.cloudGateway =>
        _promptClient.runCloudSecretaryPrompt(
          key,
          prompt: prompt,
          gatewayBaseUrl: routeConfig.cloudGatewayBaseUrl ?? '',
          idToken: routeConfig.cloudIdToken ?? '',
          modelName: routeConfig.cloudModelName ?? '',
          purpose: secretaryAiPurpose,
        ),
      SecretaryAiRouteKind.localOnly => Future<String>.value('{}'),
    };
  }

  Map<String, Object?> _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) return const <String, Object?>{};
      try {
        decoded = jsonDecode(trimmed.substring(start, end + 1));
      } catch (_) {
        return const <String, Object?>{};
      }
    }
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    return const <String, Object?>{};
  }
}

final class SecretaryAiPlanningEnhancement {
  const SecretaryAiPlanningEnhancement({
    required this.route,
    required this.planningExplanation,
    required this.missingNextActions,
  });

  const SecretaryAiPlanningEnhancement.empty({required this.route})
      : planningExplanation = null,
        missingNextActions = const <SecretaryAiMissingNextActionSuggestion>[];

  factory SecretaryAiPlanningEnhancement.fromJson(
    Map<String, Object?> json, {
    required String route,
  }) {
    return SecretaryAiPlanningEnhancement(
      route: route,
      planningExplanation: _stringValue(json['planning_explanation']),
      missingNextActions: _missingNextActions(json['missing_next_actions']),
    );
  }

  final String route;
  final String? planningExplanation;
  final List<SecretaryAiMissingNextActionSuggestion> missingNextActions;

  bool get isEmpty =>
      (planningExplanation == null || planningExplanation!.trim().isEmpty) &&
      missingNextActions.isEmpty;

  SecretaryPlan applyToPlan(SecretaryPlan plan) {
    if (isEmpty) return plan;
    final suggestionsByTodoId = {
      for (final item in missingNextActions) item.todoId: item.suggestion,
    };
    return plan.copyWith(
      route: route,
      explanation: planningExplanation,
      sections: plan.sections.copyWith(
        missingNextAction: [
          for (final item in plan.sections.missingNextAction)
            item.copyWith(
              reason: suggestionsByTodoId[item.todoId] ?? item.reason,
            ),
        ],
      ),
    );
  }

  static List<SecretaryAiMissingNextActionSuggestion> _missingNextActions(
    Object? value,
  ) {
    if (value is! List) {
      return const <SecretaryAiMissingNextActionSuggestion>[];
    }
    final out = <SecretaryAiMissingNextActionSuggestion>[];
    for (final item in value) {
      if (item is! Map) continue;
      final todoId = _stringValue(item['todo_id']);
      final suggestion = _stringValue(item['suggestion']);
      if (todoId == null || suggestion == null) continue;
      out.add(
        SecretaryAiMissingNextActionSuggestion(
          todoId: todoId,
          suggestion: suggestion,
        ),
      );
    }
    return out;
  }
}

final class SecretaryAiMissingNextActionSuggestion {
  const SecretaryAiMissingNextActionSuggestion({
    required this.todoId,
    required this.suggestion,
  });

  final String todoId;
  final String suggestion;
}

final class SecretaryAiMemoryProposalDraft {
  const SecretaryAiMemoryProposalDraft({
    required this.kind,
    required this.title,
    required this.body,
    required this.confidence,
    required this.supersedesCandidateIds,
  });

  factory SecretaryAiMemoryProposalDraft.fromProposal(
    SecretaryMemoryProposal proposal,
  ) {
    return SecretaryAiMemoryProposalDraft(
      kind: proposal.kind,
      title: proposal.title,
      body: proposal.body,
      confidence: proposal.confidence,
      supersedesCandidateIds: const <String>[],
    );
  }

  factory SecretaryAiMemoryProposalDraft.fromJson(
    Map<String, Object?> json, {
    required SecretaryMemoryProposal fallback,
  }) {
    final proposalJson = json['memory_proposal'];
    final source = proposalJson is Map ? proposalJson : json;
    return SecretaryAiMemoryProposalDraft(
      kind: _stringValue(source['kind']) ?? fallback.kind,
      title: _stringValue(source['title']) ?? fallback.title,
      body: _stringValue(source['body']) ?? fallback.body,
      confidence: _doubleValue(source['confidence']) ?? fallback.confidence,
      supersedesCandidateIds: _stringList(source['supersedes_candidate_ids']),
    );
  }

  final String kind;
  final String title;
  final String body;
  final double confidence;
  final List<String> supersedesCandidateIds;
}

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
