import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
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

  test('records task focus through the runtime client', () async {
    late http.Request capturedRequest;
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    await client.recordEntityFocus(
      'vault-1',
      conversationId: 'loop_home',
      entityType: 'task',
      entityId: 'task-1',
      title: '完成周报',
    );

    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.url.path,
      '/v1/runtime/vaults/vault-1/entity-focus',
    );
    expect(jsonDecode(capturedRequest.body), {
      'conversation_id': 'loop_home',
      'entity_type': 'task',
      'entity_id': 'task-1',
      'title': '完成周报',
    });
  });

  test('fetches runtime agent state through a single view endpoint', () async {
    late http.Request capturedRequest;
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'vault_id': 'vault-1',
              'conversation_id': 'loop_home',
              'conversation_turns': [],
              'working_set_records': [],
              'tasks': [
                {
                  'id': 'task-1',
                  'kind': 'task',
                  'title': '完成周报',
                  'status': 'open',
                }
              ],
              'memory_records': [
                {
                  'id': 'memory-1',
                  'kind': 'memory',
                  'text': '任务回复请使用中文',
                }
              ],
              'recurring_reminder_rules': [],
              'approval_items': [],
              'recent_entity_refs': [],
              'latest_context_snapshot': null,
              'audit_refs': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final state = await client.fetchAgentState(
      'vault-1',
      conversationId: 'loop_home',
    );

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.url.path,
      '/v1/runtime/vaults/vault-1/agent-state',
    );
    expect(capturedRequest.url.queryParameters['conversation_id'], 'loop_home');
    expect(state.tasks.single.title, '完成周报');
    expect(state.memoryRecords.single.title, '任务回复请使用中文');
  });

  test('patches runtime approval item title through the runtime client',
      () async {
    late http.Request capturedRequest;
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          expect(
            request.url.path,
            '/v1/runtime/vaults/vault-1/approval-items/'
            'approval-recurring-rule-child-birthday-gift',
          );
          expect(request.method, 'PATCH');
          expect(jsonDecode(request.body), {
            'base_version': 1,
            'changes': {'title': '给孩子买生日礼物'},
          });
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'ok': true,
              'approval_item': {
                'id': 'approval-recurring-rule-child-birthday-gift',
                'task_id': '',
                'title': '给孩子买生日礼物',
                'kind': 'recurring_reminder_confirmation',
                'recurring_rule_id': 'recurring-rule-child-birthday-gift',
                'editable_fields': ['title'],
                'version': 2,
                'source_intent_id': 'intent-child-birthday-gift',
                'record': {
                  'id': 'recurring-rule-child-birthday-gift',
                  'title': '给孩子买生日礼物',
                },
              },
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await client.patchApprovalItem(
      'vault-1',
      approvalId: 'approval-recurring-rule-child-birthday-gift',
      baseVersion: 1,
      changes: const {'title': '给孩子买生日礼物'},
    );

    expect(capturedRequest.headers['authorization'], 'Bearer runtime-token-1');
    expect(result.title, '给孩子买生日礼物');
    expect(result.version, 2);
    expect(result.editableFields, ['title']);
    expect(result.sourceIntentId, 'intent-child-birthday-gift');
    expect(result.record?['title'], '给孩子买生日礼物');
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

  test('creates runtime conversation and sends messages with metadata',
      () async {
    final requests = <http.BaseRequest>[];
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/conversations')) {
            return http.Response(
              jsonEncode({'conversation_id': 'conversation-1'}),
              200,
            );
          }
          expect(
            request.url.path,
            '/v1/runtime/vaults/vault-1/conversations/conversation-1/messages',
          );
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          expect(decoded['message'], '把“完成周报”改到今天 20:00。');
          return http.Response(
            jsonEncode({
              'run_id': 'run-1',
              'conversation_id': 'conversation-1',
              'assistant': {
                'role': 'assistant',
                'content': '待确认：改截止时间。',
              },
              'metadata': {
                'run_id': 'run-1',
                'turn_id': 'turn-run-1',
                'conversation_id': 'conversation-1',
                'vault_id': 'vault-1',
                'response_type': 'formal_mutation_pending',
                'run_status': 'waiting_for_approval',
                'approval_required': true,
                'confidence': 0.91,
                'referenced_entities': {
                  'tasks': ['task-1'],
                },
                'proposed_mutations': [
                  {
                    'entity_type': 'task',
                    'mutation_type': 'reschedule',
                    'status': 'pending_approval',
                  }
                ],
                'applied_mutations': [],
                'draft_entities': [
                  {
                    'entity_type': 'review_note',
                    'entity_id': 'draft-1',
                  }
                ],
                'approval_items': [
                  {
                    'id': 'approval-task-1',
                    'task_id': 'task-1',
                    'title': '完成周报',
                    'kind': 'task_mutation_confirmation',
                  }
                ],
                'tool_trace_ids': ['trace-vault-1', 'trace-model-1'],
                'provider_trace_id': 'provider-trace-1',
                'state_snapshot_after': {
                  'pending_task_mutations': ['task-1'],
                },
                'requires_high_cost_confirmation': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final conversationId = await client.createConversation('vault-1');
    final run = await client.sendConversationMessage(
      'vault-1',
      conversationId: conversationId,
      message: '把“完成周报”改到今天 20:00。',
    );

    expect(conversationId, 'conversation-1');
    expect(run.runId, 'run-1');
    expect(run.assistantContent, '待确认：改截止时间。');
    expect(run.metadata.responseType, 'formal_mutation_pending');
    expect(run.metadata.runStatus, 'waiting_for_approval');
    expect(run.metadata.approvalRequired, isTrue);
    expect(run.metadata.confidence, 0.91);
    expect(run.metadata.referencedEntities['tasks'], ['task-1']);
    expect(
        run.metadata.proposedMutations.single['mutation_type'], 'reschedule');
    expect(run.metadata.appliedMutations, isEmpty);
    expect(run.metadata.draftEntities.single['entity_id'], 'draft-1');
    expect(
        run.metadata.approvalItems.single.kind, 'task_mutation_confirmation');
    expect(run.metadata.toolTraceIds, ['trace-vault-1', 'trace-model-1']);
    expect(run.metadata.providerTraceId, 'provider-trace-1');
    expect(
      run.metadata.stateSnapshotAfter?['pending_task_mutations'],
      ['task-1'],
    );
    expect(run.metadata.requiresHighCostConfirmation, isFalse);
    expect(requests.map((request) => request.url.path), [
      '/v1/runtime/vaults/vault-1/conversations',
      '/v1/runtime/vaults/vault-1/conversations/conversation-1/messages',
    ]);
  });

  test('fetches runtime conversation run results by id', () async {
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/runtime/vaults/vault-1/runs/run-1');
          return http.Response(
            jsonEncode({
              'run_id': 'run-1',
              'conversation_id': 'conversation-1',
              'assistant': {'content': 'done'},
              'metadata': {
                'run_id': 'run-1',
                'turn_id': 'turn-run-1',
                'conversation_id': 'conversation-1',
                'vault_id': 'vault-1',
                'response_type': 'unknown_future_type',
                'run_status': 'unknown_future_status',
                'approval_required': false,
              },
            }),
            200,
          );
        }),
      ),
    );

    final run = await client.fetchRun('vault-1', runId: 'run-1');

    expect(run.metadata.responseType, 'unknown_future_type');
    expect(run.metadata.runStatus, 'unknown_future_status');
  });

  test('uploads conversation attachments through the runtime vault proxy',
      () async {
    late http.Request capturedRequest;
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({'ok': true, 'blob_id': 'sha-1'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    await client.uploadVaultAttachment(
      'vault-1',
      attachmentId: 'sha-1',
      filename: 'qa-ocr-sample.png',
      mimeType: 'image/png',
      mediaType: 'image',
      bytes: const <int>[1, 2, 3],
    );

    expect(
      capturedRequest.url.path,
      '/v1/runtime/vaults/vault-1/blobs/sha-1',
    );
    expect(capturedRequest.method, 'PUT');
    expect(capturedRequest.headers['authorization'], 'Bearer runtime-token-1');
    expect(capturedRequest.headers['content-type'], 'image/png');
    expect(capturedRequest.headers['x-attachment-id'], 'sha-1');
    expect(capturedRequest.headers['x-sha256'], 'sha-1');
    expect(capturedRequest.headers['x-filename'], 'qa-ocr-sample.png');
    expect(capturedRequest.headers['x-media-type'], 'image');
    expect(capturedRequest.bodyBytes, const <int>[1, 2, 3]);
  });

  test('fetches runtime attachment bytes through the vault proxy', () async {
    late http.Request capturedRequest;
    final client = SecretaryRuntimeClient(
      apiClient: RuntimeApiClient(
        connectionStore: RuntimeConnectionStore(),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response.bytes(
            const <int>[1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );

    final bytes = await client.fetchVaultAttachmentBytes(
      'vault-1',
      attachmentId: 'sha-1',
    );

    expect(
      capturedRequest.url.path,
      '/v1/runtime/vaults/vault-1/blobs/sha-1',
    );
    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.headers['authorization'], 'Bearer runtime-token-1');
    expect(bytes, const <int>[1, 2, 3]);
  });

  test('hosted managed pro sender routes runtime chat through cloud gateway',
      () async {
    final requests = <http.BaseRequest>[];
    final sender = SecretaryRuntimeConversationSender.hostedManagedPro(
      apiBaseUrl: 'https://gateway.test/root/',
      hostedSessionTokenGetter: () async => 'hosted-id-token-1',
      httpClient: MockClient((request) async {
        requests.add(request);
        expect(
          request.url.path,
          '/v1/runtime/vaults/managed-user-1/conversations/loop_home/messages',
        );
        expect(
          request.headers['authorization'],
          'Bearer hosted-id-token-1',
        );
        expect(
          request.headers.containsKey('x-secondloop-hosted-session'),
          isFalse,
        );
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        expect(decoded['message'], '帮我创建一个任务：完成周报。');
        return http.Response(
          jsonEncode({
            'run_id': 'run-1',
            'conversation_id': 'loop_home',
            'assistant': {'content': '已创建任务：完成周报。'},
            'metadata': {
              'run_id': 'run-1',
              'turn_id': 'turn-run-1',
              'conversation_id': 'loop_home',
              'vault_id': 'managed-user-1',
              'response_type': 'task_created',
              'run_status': 'completed',
              'approval_required': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await sender.send(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '帮我创建一个任务：完成周报。',
    );

    expect(result.assistantContent, '已创建任务：完成周报。');
    expect(requests, hasLength(1));
  });
}
