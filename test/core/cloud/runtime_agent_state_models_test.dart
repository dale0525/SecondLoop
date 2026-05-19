import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';

void main() {
  test('parses runtime agent state without mapping to local store models', () {
    final state = RuntimeAgentState.fromJson(const {
      'vault_id': 'uid_1',
      'conversation_id': 'loop_home',
      'conversation_turns': [
        {
          'turn_id': 'turn-1',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'role': 'user',
          'content': '帮我创建一个任务：完成周报。',
          'attachment_refs': ['attachment-1'],
          'created_at_ms': 1700000000000,
        },
        {
          'turn_id': 'turn-2',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'role': 'assistant',
          'content': 'Apple 发布了新产品。',
          'web_research_drafts': [
            {
              'query': 'Apple 发布会',
              'summary': 'Apple 发布了新产品。',
              'citations': [
                {
                  'title': 'Apple Newsroom',
                  'url': 'https://www.apple.com/newsroom/',
                  'domain': 'www.apple.com',
                  'fetched_at_ms': 1700000000100,
                }
              ],
            }
          ],
          'created_at_ms': 1700000000200,
        }
      ],
      'working_set_records': [
        {
          'id': 'task-1',
          'kind': 'task',
          'title': '完成周报',
          'status': 'open',
        },
        {
          'id': 'memory-1',
          'kind': 'memory',
          'text': '任务回复请使用中文',
        },
      ],
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
      'approval_items': [
        {'id': 'approval-1', 'kind': 'memory_confirmation'}
      ],
      'recent_entity_refs': [
        {'entity_id': 'task-1'}
      ],
      'latest_context_snapshot': {
        'id': 'context-snapshot-1',
        'generated_at_ms': 1700000000100,
        'packet': {
          'conversation_id': 'loop_home',
          'working_set': {'records': []},
        },
      },
      'audit_refs': [
        {'id': 'audit-1', 'kind': 'conversation_turn'}
      ],
    });

    expect(state.vaultId, 'uid_1');
    expect(state.conversationId, 'loop_home');
    expect(state.conversationTurns.first.attachmentRefs, ['attachment-1']);
    expect(
      state.conversationTurns.last.citationsJson,
      contains('https://www.apple.com/newsroom/'),
    );
    expect(
        state.conversationTurns.last.citationsJson, contains('web_research'));
    expect(state.tasks.single.title, '完成周报');
    expect(state.memoryRecords.single.title, '任务回复请使用中文');
    expect(state.approvalItems.single['id'], 'approval-1');
    expect(state.latestContextSnapshot?.id, 'context-snapshot-1');
    expect(
      state.latestContextSnapshot?.packet['conversation_id'],
      'loop_home',
    );
    expect(state.auditRefs.single['kind'], 'conversation_turn');
  });
}
