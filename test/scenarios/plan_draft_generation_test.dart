import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test('plan draft generation scenario returns draft semantics and artifacts',
      () async {
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/fixtures/working-set') ||
          request.url.path.endsWith('/provider-simulation') ||
          request.url.path.endsWith('/reset')) {
        return jsonScenarioResponse({'ok': true});
      }
      if (request.url.path.endsWith('/conversations')) {
        return jsonScenarioResponse({'conversation_id': 'conversation-1'});
      }
      if (request.url.path.endsWith('/messages')) {
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'plan_draft',
            content: '先完成周报，再处理部署方案。',
            referencedEntities: {
              'tasks': ['task-1', 'task-2'],
            },
            draftEntities: const [
              {'entity_type': 'plan_draft'},
            ],
          ),
        );
      }
      if (request.url.path.endsWith('/artifact-bundle')) {
        return jsonScenarioResponse(
          buildScenarioArtifactBundle(
            transcript: const [
              {'role': 'user', 'content': '请根据我当前的任务，帮我排一个今天的执行计划。'},
              {'role': 'assistant', 'content': '先完成周报，再处理部署方案。'},
            ],
            changedPaths: const ['agent_state.plan_drafts'],
            runLogs: const [
              {'kind': 'plan_generation'},
            ],
            toolCallLogs: const [
              {'tool_name': 'vault_service.fetch_working_set'},
            ],
            providerTraces: const [
              {'provider': 'openai'},
            ],
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await client.injectWorkingSetFixtures(
      vaultId: 'vault-1',
      tasks: const [
        {'id': 'task-1', 'title': '完成周报', 'status': 'todo'},
        {
          'id': 'task-2',
          'title': '整理 Cloudflare 部署方案',
          'status': 'in_progress'
        },
      ],
    );
    await client.configureProviderSimulation(
      vaultId: 'vault-1',
      provider: 'openai',
      purpose: 'plan_generation',
      simulation: const {'mode': 'fixed_response'},
    );
    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '请根据我当前的任务，帮我排一个今天的执行计划。',
    );
    final artifactBundle = await client.fetchArtifactBundle(runId: run.runId);

    expectRuntimeResponseType(run, 'plan_draft');
    expectApprovalRequired(run, value: false);
    expect(run.metadata['draft_entities'], isNotEmpty);
    expect(
      artifactBundle.stateDiff['changed_paths'],
      contains('agent_state.plan_drafts'),
    );
    expect(artifactBundle.toolCallLogs.single['tool_name'],
        contains('working_set'));

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
