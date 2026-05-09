import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test('external tool block scenario refuses undeclared side effects',
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
            responseType: 'external_side_effect_blocked',
            content: '当前没有可安全使用的外部发信工具。',
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '直接把周报邮件发给 Alice。',
    );

    expectRuntimeResponseType(run, 'external_side_effect_blocked');
    expectApprovalRequired(run, value: false);
    expect(run.assistantContent, contains('外部发信工具'));

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
