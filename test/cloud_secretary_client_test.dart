import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/cloud_secretary_client.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';

void main() {
  test('CloudSecretaryClient fetches scheduled planning results', () async {
    final requests = <http.Request>[];
    final client = CloudSecretaryClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'cloud-plan-1',
                'kind': 'daily_plan',
                'status': 'ready',
                'title': 'Cloud daily plan',
                'body': 'Generated from Agent Digest.',
                'generated_at_ms': 1700000000000,
                'digest_generated_at_ms': 1699990000000,
                'skip_reason': null,
                'items': [
                  {
                    'id': 'item-1',
                    'todo_id': 'todo-1',
                    'title': 'Submit review',
                    'reason': 'Upcoming deadline',
                    'requires_confirmation': true,
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await client.fetchPlanningResults(
      cloudGatewayBaseUrl: 'https://gateway.test',
      idToken: 'token-1',
      sinceMs: 1699900000000,
    );

    expect(results, hasLength(1));
    expect(results.single.id, 'cloud-plan-1');
    expect(results.single.digestGeneratedAtMs, 1699990000000);
    expect(results.single.items.single.requiresConfirmation, isTrue);
    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.toString(),
      'https://gateway.test/v1/secretary/planning-results?since_ms=1699900000000',
    );
    expect(requests.single.headers['authorization'], 'Bearer token-1');
  });

  test('SecretaryController converts Cloud result into reviewable plan', () {
    final controller = SecretaryController(
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );

    final plan = controller.planFromCloudResult(
      const CloudSecretaryPlanningResult(
        id: 'cloud-plan-1',
        kind: 'daily_plan',
        status: 'ready',
        title: 'Cloud daily plan',
        body: 'Generated from Agent Digest.',
        generatedAtMs: 1700000000000,
        digestGeneratedAtMs: 1699990000000,
        skipReason: null,
        items: [
          CloudSecretaryPlanningItem(
            id: 'item-1',
            todoId: 'todo-1',
            title: 'Submit review',
            reason: 'Upcoming deadline',
            requiresConfirmation: true,
          ),
        ],
      ),
    );

    expect(plan.route, 'cloud_agent_digest');
    expect(plan.generatedBy, 'cloud');
    expect(plan.digestGeneratedAtMs, 1699990000000);
    expect(plan.sections.focus, hasLength(1));
    expect(plan.sections.focus.single.requiresConfirmation, isTrue);
  });

  test('SecretaryController surfaces Cloud stale skip reason for review', () {
    final controller = SecretaryController(
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );

    final plan = controller.planFromCloudResult(
      const CloudSecretaryPlanningResult(
        id: 'cloud-plan-stale',
        kind: 'daily_plan',
        status: 'skipped',
        title: 'Cloud daily plan skipped',
        body: 'Agent Digest is stale.',
        generatedAtMs: 1700000000000,
        digestGeneratedAtMs: 1690000000000,
        skipReason: 'digest_stale',
        items: [],
      ),
    );

    expect(plan.sections.isEmpty, isTrue);
    expect(plan.skipReason, 'digest_stale');
    expect(plan.explanation, contains('Agent Digest is stale'));
  });
}
