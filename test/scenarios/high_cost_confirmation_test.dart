import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';

void main() {
  test('runtime metadata exposes high-cost confirmation reason', () {
    final run = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'assistant': {
        'role': 'assistant',
        'content': 'High-cost confirmation required.',
      },
      'metadata': {
        'run_id': 'run-1',
        'turn_id': 'turn-run-1',
        'conversation_id': 'conversation-1',
        'vault_id': 'vault-1',
        'response_type': 'high_cost_confirmation',
        'run_status': 'waiting_for_approval',
        'approval_required': true,
        'requires_high_cost_confirmation': true,
        'approval_items': [
          {
            'id': 'approval-high-cost-long-context',
            'kind': 'high_cost_confirmation',
            'title': 'Confirm high-cost work',
            'reason': 'long_context',
            'cost_label': 'high',
          },
        ],
      },
    });

    expect(run.metadata.responseType, 'high_cost_confirmation');
    expect(run.metadata.requiresHighCostConfirmation, isTrue);
    expect(run.metadata.approvalItems.single.kind, 'high_cost_confirmation');
    expect(run.metadata.approvalItems.single.reason, 'long_context');
  });
}
