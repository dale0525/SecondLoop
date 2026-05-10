import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';

void main() {
  test('runtime metadata exposes cited web research drafts', () {
    final run = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'assistant': {
        'role': 'assistant',
        'content': '已保存调研草稿。',
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
            'entity_type': 'web_research_draft',
            'entity_id': 'web-research-draft-hermes-agent-openclaw',
          },
        ],
        'web_research_drafts': [
          {
            'query': 'Hermes Agent OpenClaw capability comparison',
            'search_count': 5,
            'fetch_count': 3,
            'citations': [
              {
                'title': 'Hermes Agent docs',
                'url': 'https://example.com/hermes',
                'domain': 'example.com',
                'fetched_at_ms': 1700000000000,
              },
            ],
            'summary':
                'Hermes and OpenClaw differ in orchestration boundaries.',
          },
        ],
      },
    });

    expect(
        run.metadata.draftEntities.single['entity_type'], 'web_research_draft');
    expect(run.metadata.webResearchDrafts.single['search_count'], 5);
    expect(
      (run.metadata.webResearchDrafts.single['citations'] as List).single,
      containsPair('url', 'https://example.com/hermes'),
    );
  });
}
