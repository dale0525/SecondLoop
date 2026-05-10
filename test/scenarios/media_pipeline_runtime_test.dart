import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';

void main() {
  test('runtime metadata exposes media result summaries and citations', () {
    final run = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'assistant': {
        'role': 'assistant',
        'content': '会议总结：检查发布清单。',
      },
      'metadata': {
        'run_id': 'run-1',
        'turn_id': 'turn-run-1',
        'conversation_id': 'conversation-1',
        'vault_id': 'vault-1',
        'response_type': 'summary',
        'run_status': 'completed',
        'approval_required': false,
        'draft_entities': [
          {
            'entity_type': 'media_result',
            'entity_id': 'media-result-attachment-1',
          },
        ],
        'media_results': [
          {
            'kind': 'media_result',
            'attachment_id': 'attachment-1',
            'media_type': 'audio',
            'summary': '会议总结：检查发布清单。',
            'citations': [
              {
                'title': 'meeting.m4a',
                'url': 'vault://attachment-1',
                'domain': 'vault',
                'fetched_at_ms': 1700000000000,
              },
            ],
            'status': 'completed',
          },
        ],
      },
    });

    expect(run.metadata.draftEntities.single['entity_type'], 'media_result');
    expect(run.metadata.mediaResults.single['attachment_id'], 'attachment-1');
    expect(
      (run.metadata.mediaResults.single['citations'] as List).single,
      containsPair('domain', 'vault'),
    );
  });
}
