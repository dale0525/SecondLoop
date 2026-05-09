import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://runtime.example/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          authToken: 'runtime-token-1',
          capabilityManifestId: 'manifest-self-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://runtime.example/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );
  });

  test('fetches planning and review data through the runtime client', () async {
    final requests = <http.BaseRequest>[];
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/plans')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'plan-1',
                    'title': 'Runtime plan draft',
                    'generated_at_ms': 1700000000000,
                    'items': [
                      {
                        'id': 'plan-item-1',
                        'task_id': 'task-1',
                        'title': 'Submit review',
                        'status': 'open',
                        'requires_confirmation': true,
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'approval-1',
                  'task_id': 'task-1',
                  'title': 'Submit review',
                  'kind': 'reminder_confirmation',
                },
              ],
            }),
            200,
          );
        }),
      ),
    );

    final plans = await client.fetchPlans('vault-1');
    final approvals = await client.fetchApprovals('vault-1');

    expect(plans.single.items.single.requiresConfirmation, isTrue);
    expect(approvals.single.kind, 'reminder_confirmation');
    expect(requests.map((request) => request.url.path), [
      '/v1/runtime/vaults/vault-1/plans',
      '/v1/runtime/vaults/vault-1/approvals',
    ]);
  });

  test(
      'request plan refresh uses runtime profile routing and not digest semantics',
      () async {
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/runtime/vaults/vault-1/plans/generate');
          expect(request.headers['authorization'], 'Bearer runtime-token-1');
          final decoded = jsonDecode(request.body);
          expect(decoded['runtime_mode'], 'self_managed');
          expect(decoded.containsKey('digest_generated_at_ms'), isFalse);
          return http.Response(
            jsonEncode({
              'plan': {
                'id': 'plan-1',
                'title': 'Runtime plan draft',
                'generated_at_ms': 1700000000000,
                'items': [],
              },
            }),
            200,
          );
        }),
      ),
    );

    final plan = await client.requestPlanRefresh('vault-1');

    expect(plan.id, 'plan-1');
  });

  test('fetches runtime capabilities through the shared runtime endpoint',
      () async {
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'capabilities': ['chat', 'working_set'],
            }),
            200,
          );
        }),
      ),
    );

    expect(
      await client.fetchRuntimeCapabilities(),
      ['chat', 'working_set'],
    );
  });
}
