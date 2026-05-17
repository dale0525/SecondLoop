import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_ai_service.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

import 'test_backend.dart';

void main() {
  test('no BYOK or Cloud keeps local planning without AI calls', () async {
    final now = DateTime(2026, 4, 29, 9);
    final promptClient = _PromptClient();
    final controller = SecretaryController(
      backend: _PlanningBackend(),
      aiService: SecretaryAiService(promptClient: promptClient),
      aiRouteConfig: const SecretaryAiRouteConfig.localOnly(),
      planningEngine: RuleBasedPlanningEngine(nowLocal: () => now),
    );

    final plan = await controller.generateAndPersistPlan(
      Uint8List(32),
      [
        _todo(
            id: 't1',
            title: 'Submit beta review',
            dueAtMs: now.millisecondsSinceEpoch)
      ],
      nowMs: now.millisecondsSinceEpoch,
    );

    expect(plan.route, 'local_rules');
    expect(plan.itemCount, 1);
    expect(promptClient.byokCalls, 0);
    expect(promptClient.cloudCalls, 0);
  });

  test('BYOK route can enhance a memory proposal without writing memory',
      () async {
    final promptClient = _PromptClient(
      responseJson: jsonEncode({
        'memory_proposal': {
          'kind': 'preference',
          'title': 'Morning meeting preference',
          'body': 'The user prefers meetings in the morning.',
          'confidence': 0.91,
          'supersedes_candidate_ids': ['memory-old'],
        },
      }),
    );
    final service = SecretaryAiService(promptClient: promptClient);

    final result = await service.enhanceMemoryProposal(
      Uint8List(32),
      proposal: const SecretaryMemoryProposal(
        id: 'proposal-1',
        sourceMessageId: 'm1',
        kind: 'preference',
        title: 'morning meetings',
        body: 'Remember that I prefer morning meetings.',
        confidence: 0.8,
        createdAtMs: 100,
      ),
      routeConfig: const SecretaryAiRouteConfig.byok(),
    );

    expect(result.title, 'Morning meeting preference');
    expect(result.body, 'The user prefers meetings in the morning.');
    expect(result.supersedesCandidateIds, ['memory-old']);
    expect(promptClient.byokCalls, 1);
    expect(promptClient.cloudCalls, 0);
    expect(promptClient.lastPrompt, contains('"purpose":"secretary"'));
  });

  test('Cloud entitled route calls gateway with secretary purpose', () async {
    final promptClient = _PromptClient(
      responseJson: jsonEncode({
        'planning_explanation': 'Start with the overdue review.',
        'missing_next_actions': [
          {'todo_id': 't1', 'suggestion': 'Choose the next review owner.'},
        ],
      }),
    );
    final service = SecretaryAiService(promptClient: promptClient);

    final route = await SecretaryAiService.resolveRoute(
      _RouteBackend(hasByok: false),
      Uint8List(32),
      cloudIdToken: 'token',
      cloudGatewayBaseUrl: 'https://gateway.example',
      cloudModelName: 'gpt-4o-mini',
      subscriptionStatus: SubscriptionStatus.entitled,
    );

    final enhancement = await service.enhancePlan(
      Uint8List(32),
      localPlan: _plan(),
      routeConfig: route,
      localeTag: 'en-US',
    );

    expect(route.kind, SecretaryAiRouteKind.cloudGateway);
    expect(enhancement.planningExplanation, 'Start with the overdue review.');
    expect(promptClient.cloudCalls, 1);
    expect(promptClient.lastCloudPurpose, 'secretary');
    expect(promptClient.lastCloudGatewayBaseUrl, 'https://gateway.example');
    expect(promptClient.lastCloudIdToken, 'token');
    expect(promptClient.lastCloudModelName, 'gpt-4o-mini');
  });
}

final class _PromptClient implements SecretaryAiPromptClient {
  _PromptClient({this.responseJson = '{}'});

  final String responseJson;
  int byokCalls = 0;
  int cloudCalls = 0;
  String? lastPrompt;
  String? lastCloudGatewayBaseUrl;
  String? lastCloudIdToken;
  String? lastCloudModelName;
  String? lastCloudPurpose;

  @override
  Future<String> runByokSecretaryPrompt(
    Uint8List key, {
    required String prompt,
  }) async {
    byokCalls += 1;
    lastPrompt = prompt;
    return responseJson;
  }

  @override
  Future<String> runCloudSecretaryPrompt(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String purpose,
  }) async {
    cloudCalls += 1;
    lastPrompt = prompt;
    lastCloudGatewayBaseUrl = gatewayBaseUrl;
    lastCloudIdToken = idToken;
    lastCloudModelName = modelName;
    lastCloudPurpose = purpose;
    return responseJson;
  }
}

final class _RouteBackend extends TestAppBackend {
  _RouteBackend({required this.hasByok});

  final bool hasByok;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    if (!hasByok) return const <LlmProfile>[];
    return const <LlmProfile>[
      LlmProfile(
        id: 'p1',
        name: 'BYOK',
        providerType: 'openai-compatible',
        modelName: 'gpt-4o-mini',
        isActive: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ];
  }
}

SecretaryPlan _plan() {
  return const SecretaryPlan(
    id: 'plan-1',
    title: 'Daily plan',
    generatedAtMs: 100,
    route: 'local_rules',
    sections: SecretaryPlanSections(
      focus: <SecretaryPlanItem>[],
      dueSoon: <SecretaryPlanItem>[],
      needsDecision: <SecretaryPlanItem>[],
      missingNextAction: <SecretaryPlanItem>[
        SecretaryPlanItem(
          id: 'item-1',
          todoId: 't1',
          title: 'Submit beta review',
          reason: 'No schedule or next action',
        ),
      ],
    ),
  );
}

Todo _todo({
  required String id,
  required String title,
  int? dueAtMs,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
    status: 'open',
    createdAtMs: platformIntFromInt(1),
    updatedAtMs: platformIntFromInt(1),
  );
}

final class _PlanningBackend implements SecretaryBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    return const <PlanningOutputRecord>[];
  }

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    return PlanningOutputRecord(
      id: id,
      kind: kind,
      title: title,
      body: body,
      itemsJson: itemsJson,
      sourceRefsJson: sourceRefsJson,
      route: route,
      state: state,
      createdAtMs: platformIntFromInt(createdAtMs),
      updatedAtMs: platformIntFromInt(updatedAtMs),
      expiresAtMs: expiresAtMs == null ? null : platformIntFromInt(expiresAtMs),
    );
  }
}
