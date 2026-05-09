import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test(
      'high cost confirmation scenario requires explicit confirmation metadata',
      () async {
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/conversations') ||
          request.url.path.endsWith('/reset')) {
        return jsonScenarioResponse(
          request.url.path.endsWith('/conversations')
              ? {'conversation_id': 'conversation-1'}
              : {'ok': true},
        );
      }
      if (request.url.path.endsWith('/messages')) {
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'high_cost_confirmation',
            content: '该请求需要高成本确认。',
            status: 'waiting_approval',
            approvalRequired: true,
            requiresHighCostConfirmation: true,
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '深度分析我过去一年的全部对话、任务和记忆，生成完整复盘报告。',
    );

    expectRuntimeResponseType(run, 'high_cost_confirmation');
    expectApprovalRequired(run, value: true);
    expect(run.metadata['requires_high_cost_confirmation'], isTrue);

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
