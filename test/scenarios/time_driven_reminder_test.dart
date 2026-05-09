import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/cloud_runtime_test_assertions.dart';
import '../../test_helpers/runtime_test_scenario_client.dart';

void main() {
  test('time-driven reminder scenario advances time and triggers due alarms',
      () async {
    final client = await createRuntimeTestScenarioClient((request) async {
      if (request.url.path.endsWith('/fixtures/working-set') ||
          request.url.path.contains('/approvals/') &&
              request.url.path.endsWith('/approve') ||
          request.url.path.endsWith('/jobs/run') ||
          request.url.path.endsWith('/reset')) {
        return jsonScenarioResponse({'ok': true});
      }
      if (request.url.path.endsWith('/conversations')) {
        return jsonScenarioResponse({'conversation_id': 'conversation-1'});
      }
      if (request.url.path.endsWith('/messages')) {
        return jsonScenarioResponse(
          buildScenarioRunResult(
            responseType: 'reminder_candidate',
            content: '待确认：明天 9 点提醒开会。',
            status: 'waiting_approval',
            approvalRequired: true,
            proposedMutations: const [
              {
                'entity_type': 'reminder',
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
              id: 'approval-reminder-1',
              kind: 'reminder_confirmation',
            ),
          ],
        });
      }
      if (request.url.path.endsWith('/advance-time')) {
        return jsonScenarioResponse({'now_ms': 1700000100000});
      }
      if (request.url.path.endsWith('/alarms/trigger-all-due')) {
        return jsonScenarioResponse({
          'ok': true,
          'reminders': const [
            {'id': 'reminder-1', 'triggered_at_ms': 1700000100000},
          ],
        });
      }
      if (request.url.path.endsWith('/checkpoints')) {
        return jsonScenarioResponse({
          'items': const [
            {'kind': 'alarm_triggered'},
          ],
        });
      }
      if (request.url.path.endsWith('/state-diff')) {
        return jsonScenarioResponse(
          buildScenarioStateDiff(
            changedPaths: const ['agent_state.checkpoints'],
          ),
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await client.injectWorkingSetFixtures(
      vaultId: 'vault-1',
      tasks: const [
        {'id': 'task-1', 'title': '预约牙医复诊', 'status': 'todo'},
      ],
    );
    final conversation = await client.createConversation('vault-1');
    final run = await client.sendMessage(
      vaultId: 'vault-1',
      conversationId: conversation.conversationId,
      message: '明天上午 9 点提醒我开会。',
    );
    final approvals = await client.fetchApprovals('vault-1');
    await client.approve('vault-1', approvals.single.id);
    expect(await client.advanceTime(3600000), 1700000100000);
    await client.runJob(vaultId: 'vault-1', job: 'reminders');
    final triggered = await client.triggerAllDueAlarms('vault-1');
    final checkpoints = await client.fetchCheckpoints('vault-1');
    final diff = await client.fetchStateDiff(
      beforeLabel: 'before',
      afterLabel: 'after',
    );

    expectRuntimeResponseType(run, 'reminder_candidate');
    expectApprovalKind(approvals.single, 'reminder_confirmation');
    expect((triggered['reminders'] as List).single['id'], 'reminder-1');
    expect((checkpoints.single['kind']), 'alarm_triggered');
    expectChangedPath(diff, 'agent_state.checkpoints');

    await client.reset(vaultId: 'vault-1');
    client.dispose();
  });
}
