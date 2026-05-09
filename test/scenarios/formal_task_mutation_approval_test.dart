import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test(
      'formal task mutation scenario keeps task status changes behind approval',
      () async {
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/fixtures/working-set') ||
          request.url.path.endsWith('/reset') ||
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
            responseType: 'formal_mutation_pending',
            content: '待确认：把完成周报标记为已完成。',
            status: 'waiting_approval',
            approvalRequired: true,
            referencedEntities: {
              'tasks': ['task-1'],
            },
            proposedMutations: const [
              {
                'entity_type': 'task',
                'mutation_type': 'update',
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
              id: 'approval-task-1',
              kind: 'task_mutation_confirmation',
              extra: const {'task_id': 'task-1'},
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

    await client.injectWorkingSetFixtures(
      vaultId: 'vault-1',
      tasks: const [
        {'id': 'task-1', 'title': '完成周报', 'status': 'todo'},
      ],
    );
    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '把“完成周报”标记为已完成。',
    );
    final approvals = await client.fetchApprovals('vault-1');
    await client.approve('vault-1', approvals.single.id);
    final diff = await client.fetchStateDiff(
      beforeLabel: 'before',
      afterLabel: 'after',
    );

    expectRuntimeResponseType(run, 'formal_mutation_pending');
    expectApprovalRequired(run, value: true);
    expectApprovalKind(approvals.single, 'task_mutation_confirmation');
    expectChangedPath(diff, 'vault_snapshot.working_set.records');

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
