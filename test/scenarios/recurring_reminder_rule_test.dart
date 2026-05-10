import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';

void main() {
  test('runtime metadata exposes recurring reminder approval details', () {
    final run = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'assistant': {
        'role': 'assistant',
        'content': 'Pending recurring reminder approval.',
      },
      'metadata': {
        'run_id': 'run-1',
        'turn_id': 'turn-run-1',
        'conversation_id': 'conversation-1',
        'vault_id': 'vault-1',
        'response_type': 'recurring_reminder_candidate',
        'run_status': 'waiting_for_approval',
        'approval_required': true,
        'proposed_mutations': [
          {
            'entity_type': 'recurring_reminder_rule',
            'mutation_type': 'create',
            'status': 'pending_approval',
            'record_id': 'recurring-rule-child-birthday-gift',
          },
        ],
        'approval_items': [
          {
            'id': 'approval-recurring-rule-child-birthday-gift',
            'kind': 'recurring_reminder_confirmation',
            'title': '提醒买礼物',
            'recurring_rule_id': 'recurring-rule-child-birthday-gift',
            'record': {
              'kind': 'recurring_reminder_rule',
              'id': 'recurring-rule-child-birthday-gift',
              'schedule': {
                'type': 'yearly_relative_date',
                'source_memory_id': 'memory-child-birthday',
                'offset_days': -1,
              },
            },
          },
        ],
      },
    });

    final approval = run.metadata.approvalItems.single;
    expect(run.metadata.responseType, 'recurring_reminder_candidate');
    expect(approval.kind, 'recurring_reminder_confirmation');
    expect(approval.recurringRuleId, 'recurring-rule-child-birthday-gift');
    expect(
      approval.record?['kind'],
      'recurring_reminder_rule',
    );
  });
}
