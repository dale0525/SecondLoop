import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/runtime_test_client.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';
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
          capabilities: [CloudRuntimeCapability('runtime_test_api')],
        ),
      ),
    );
  });

  test('drives runtime test APIs directly', () async {
    final requests = <http.Request>[];
    final client = RuntimeTestClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/bootstrap')) {
            return http.Response(
              jsonEncode({
                'vault_id': 'vault-1',
                'runtime_token': 'runtime-test-token',
                'conversation_seed': 'conversation-vault-1-seed',
                'manifest': {
                  'runtime_mode': 'self_managed',
                  'skills': [
                    {
                      'id': 'web-research',
                      'status': 'ready',
                      'provider': 'configured',
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path.contains('/runs/') &&
              request.url.path.endsWith('/result')) {
            return http.Response(
              jsonEncode({
                'schema_version': runtimeTestContractSchemaVersion,
                'run_id': 'run-1',
                'conversation_id': 'conversation-1',
                'status': 'completed',
                'assistant': {'content': 'summary output'},
                'metadata': {
                  'schema_version': runtimeTestContractSchemaVersion,
                  'response_type': 'summary',
                },
              }),
              200,
            );
          }
          if (request.url.path.contains('/conversations/') &&
              request.url.path.endsWith('/transcript')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'role': 'user', 'content': 'hello'},
                  {'role': 'assistant', 'content': 'summary output'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/approvals')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'schema_version': runtimeTestContractSchemaVersion,
                    'id': 'approval-1',
                    'kind': 'reminder_confirmation',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.contains('/approvals/')) {
            return http.Response(
              jsonEncode({
                'schema_version': runtimeTestContractSchemaVersion,
                'id': 'approval-1',
                'kind': 'reminder_confirmation',
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode({
                'schema_version': runtimeTestContractSchemaVersion,
                'run_id': 'run-1',
                'conversation_id': 'conversation-1',
                'status': 'waiting_approval',
                'assistant': {'content': 'pending approval'},
                'metadata': {
                  'schema_version': runtimeTestContractSchemaVersion,
                  'response_type': 'reminder_candidate',
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/conversations')) {
            return http.Response(
              jsonEncode({'conversation_id': 'conversation-1'}),
              200,
            );
          }
          if (request.url.path.endsWith('/artifact-bundle')) {
            return http.Response(
              jsonEncode({
                'schema_version': runtimeTestContractSchemaVersion,
                'descriptor': {
                  'kind': 'runtime_test_artifact_bundle',
                  'schema_version': runtimeTestContractSchemaVersion,
                },
                'run_id': 'run-1',
                'conversation_id': 'conversation-1',
                'transcript': [
                  {'role': 'user', 'content': 'hello'},
                ],
                'state_snapshot': {
                  'agent_state': {},
                },
                'state_diff': {
                  'schema_version': runtimeTestContractSchemaVersion,
                  'changed_paths': ['agent_state.approvals'],
                },
                'run_logs': [
                  {'kind': 'summary'},
                ],
                'tool_call_logs': [
                  {'tool_name': 'vault_service.fetch_working_set'},
                ],
                'provider_traces': [
                  {'provider': 'openai'},
                ],
                'deployment_events': [
                  {
                    'schema_version': runtimeTestContractSchemaVersion,
                    'step': 'deploy',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/state-diff')) {
            return http.Response(
              jsonEncode({
                'schema_version': runtimeTestContractSchemaVersion,
                'before_label': 'before',
                'after_label': 'after',
                'changed_paths': ['agent_state.approvals'],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/snapshot')) {
            return http.Response(
              jsonEncode({
                'agent_state': {
                  'reminders': [
                    {'id': 'reminder-1'},
                  ],
                },
                'provider_simulation': {
                  'mode': 'fixed_response',
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/checkpoints') ||
              request.url.path.endsWith('/jobs')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'kind': 'job_completed'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/jobs/run') ||
              request.url.path.endsWith('/jobs/run-all') ||
              request.url.path.endsWith('/alarms/trigger') ||
              request.url.path.endsWith('/alarms/trigger-all-due')) {
            return http.Response(
              jsonEncode({
                'ok': true,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/time/freeze')) {
            return http.Response(jsonEncode({'now_ms': 1700000005000}), 200);
          }
          if (request.url.path.endsWith('/advance-time')) {
            return http.Response(jsonEncode({'now_ms': 1700000010000}), 200);
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      ),
    );

    final bootstrap = await client.bootstrap(vaultId: 'vault-1');
    await client.injectFixtures(
      vaultId: 'vault-1',
      records: [
        {'kind': 'task', 'id': 'task-1', 'title': 'Submit review'},
      ],
    );
    await client.injectWorkingSetFixtures(
      vaultId: 'vault-1',
      tasks: [
        {'id': 'task-2', 'title': 'Prepare deployment notes'},
      ],
    );
    await client.injectAttachments(
      vaultId: 'vault-1',
      attachments: [
        {
          'blob_id': 'blob-1',
          'content_type': 'text/plain',
          'body': 'hello',
        },
      ],
    );
    await client.configureProviderSimulation(
      vaultId: 'vault-1',
      provider: 'openai',
      purpose: 'plan_generation',
      simulation: {'mode': 'fixed_response'},
    );
    expect(await client.freezeTime(1700000005000), 1700000005000);
    expect(await client.advanceTime(10000), 1700000010000);
    await client.forceJob(vaultId: 'vault-1', job: 'plans');
    await client.runJob(vaultId: 'vault-1', job: 'reminders');
    await client.runAllJobs('vault-1');
    await client.triggerAlarm(vaultId: 'vault-1', approvalId: 'approval-1');
    await client.triggerAllDueAlarms('vault-1');
    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '今晚8点提醒我提交周报。',
    );
    final approvals = await client.fetchApprovals('vault-1');
    final approval = await client.fetchApproval(
      vaultId: 'vault-1',
      approvalId: 'approval-1',
    );
    final transcript = await client.fetchTranscript('conversation-1');
    final result = await client.fetchRunResult('run-1');
    final snapshot = await client.snapshot('vault-1', label: 'before');
    final checkpoints = await client.fetchCheckpoints('vault-1');
    final jobs = await client.listJobs('vault-1');
    final diff = await client.fetchStateDiff(
      beforeLabel: 'before',
      afterLabel: 'after',
    );
    final artifactBundle = await client.fetchArtifactBundle(
      runId: 'run-1',
      snapshotLabel: 'before',
    );

    expect(bootstrap.vaultId, 'vault-1');
    expect(bootstrap.manifest['skills'], [
      {
        'id': 'web-research',
        'status': 'ready',
        'provider': 'configured',
      },
    ]);
    expect(conversation.conversationId, 'conversation-1');
    expect(run.metadata['response_type'], 'reminder_candidate');
    expect(approvals.single.id, 'approval-1');
    expect(approval.kind, 'reminder_confirmation');
    expect(transcript.length, 2);
    expect(result.assistantContent, 'summary output');
    expect(snapshot.agentState['reminders'], isNotEmpty);
    expect(snapshot.providerSimulation['mode'], 'fixed_response');
    expect(checkpoints, isNotEmpty);
    expect(jobs, isNotEmpty);
    expect(diff.changedPaths.single, 'agent_state.approvals');
    expect(artifactBundle.providerTraces.single['provider'], 'openai');
    expect(
      requests
          .any((request) => request.url.path == '/v1/runtime-test/fixtures'),
      isTrue,
    );
    for (final request in requests) {
      expect(request.headers['x-runtime-test-token'], 'runtime-test-token');
    }
  });
}
