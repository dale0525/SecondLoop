import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test(
      'provider failure and recovery scenario keeps contract stable across retries',
      () async {
    var messageCalls = 0;
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/provider-simulation') ||
          request.url.path.endsWith('/reset')) {
        return jsonScenarioResponse({'ok': true});
      }
      if (request.url.path.endsWith('/conversations')) {
        return jsonScenarioResponse({'conversation_id': 'conversation-1'});
      }
      if (request.url.path.endsWith('/messages')) {
        messageCalls += 1;
        if (messageCalls == 1) {
          return jsonScenarioResponse(
            buildScenarioRunResult(
              responseType: 'error',
              content: 'provider timeout',
              status: 'failed',
            ),
          );
        }
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'plan_draft',
            content: 'recovered plan',
            referencedEntities: const {
              'tasks': ['task-1'],
            },
            draftEntities: const [
              {'entity_type': 'plan_draft'},
            ],
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await client.configureProviderSimulation(
      vaultId: 'vault-1',
      provider: 'openai',
      purpose: 'plan_generation',
      simulation: const {'mode': 'scripted'},
    );
    final conversation = await client.createConversation('vault-1');

    final failedRun = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '请根据当前任务生成一个简短计划。',
    );
    final recoveredRun = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '请根据当前任务生成一个简短计划。',
    );

    expectRuntimeResponseType(failedRun, 'error');
    expect(failedRun.status, 'failed');
    expectRuntimeResponseType(recoveredRun, 'plan_draft');
    expect(recoveredRun.assistantContent, contains('recovered plan'));

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
