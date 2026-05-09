import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test('working set summary scenario returns fixture-backed task summary',
      () async {
    final requests = <String>[];
    final client = await createRuntimeTestScenarioClient((request) async {
      requests.add(request.url.path);
      if (request.url.path.endsWith('/fixtures/working-set') ||
          request.url.path.endsWith('/reset')) {
        return jsonScenarioResponse({'ok': true});
      }
      if (request.url.path.endsWith('/conversations')) {
        return jsonScenarioResponse({'conversation_id': 'conversation-1'});
      }
      if (request.url.path.endsWith('/messages')) {
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'summary',
            content: '完成周报\n预约牙医复诊\n整理 Cloudflare 部署方案',
            referencedEntities: {
              'tasks': ['task-1', 'task-2', 'task-3'],
            },
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await client.injectWorkingSetFixtures(
      vaultId: 'vault-1',
      tasks: const [
        {'id': 'task-1', 'title': '完成周报', 'status': 'todo'},
        {'id': 'task-2', 'title': '预约牙医复诊', 'status': 'todo'},
        {
          'id': 'task-3',
          'title': '整理 Cloudflare 部署方案',
          'status': 'in_progress'
        },
      ],
    );
    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '请总结一下我当前待办和进行中的任务。',
    );

    expectRuntimeResponseType(run, 'summary');
    expectApprovalRequired(run, value: false);
    expect(run.assistantContent, contains('完成周报'));
    expect(run.assistantContent, contains('整理 Cloudflare 部署方案'));
    expect(requests, contains('/v1/runtime-test/fixtures/working-set'));

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
