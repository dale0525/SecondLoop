import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test('memory approval scenario persists memory only after explicit approval',
      () async {
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/reset') ||
          request.url.path.contains('/approvals/') &&
              request.url.path.endsWith('/approve')) {
        return jsonScenarioResponse({'ok': true});
      }
      if (request.url.path.endsWith('/conversations')) {
        return jsonScenarioResponse({'conversation_id': 'conversation-1'});
      }
      if (request.url.path.endsWith('/messages')) {
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'memory_candidate',
            content: '待确认：记住下午安排深度工作。',
            status: 'waiting_approval',
            approvalRequired: true,
            proposedMutations: const [
              {
                'entity_type': 'memory',
                'mutation_type': 'create',
                'status': 'pending_approval',
              },
            ],
          ),
        );
      }
      if (request.url.path.endsWith('/approvals')) {
        return jsonScenarioResponse({
          'items': [
            buildScenarioApprovalItem(
              id: 'approval-memory-1',
              kind: 'memory_confirmation',
            ),
          ],
        });
      }
      if (request.url.path.endsWith('/state-diff')) {
        return jsonScenarioResponse(
          buildScenarioStateDiff(
            changedPaths: const ['vault_snapshot.working_set.records'],
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '记住：我更喜欢把深度工作安排在下午。',
    );
    final approvals = await client.fetchApprovals('vault-1');
    await client.approve('vault-1', approvals.single.id);
    final diff = await client.fetchStateDiff(
      beforeLabel: 'before',
      afterLabel: 'after',
    );

    expectRuntimeResponseType(run, 'memory_candidate');
    expectApprovalRequired(run, value: true);
    expectApprovalKind(approvals.single, 'memory_confirmation');
    expectChangedPath(diff, 'vault_snapshot.working_set.records');

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
