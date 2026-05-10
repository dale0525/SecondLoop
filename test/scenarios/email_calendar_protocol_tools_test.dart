import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';

void main() {
  test('runtime metadata exposes email and calendar approval targets', () {
    final emailRun = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'assistant': {'role': 'assistant', 'content': '邮件草稿待确认。'},
      'metadata': {
        'run_id': 'run-1',
        'turn_id': 'turn-run-1',
        'conversation_id': 'conversation-1',
        'vault_id': 'vault-1',
        'response_type': 'email_draft',
        'run_status': 'waiting_for_approval',
        'approval_required': true,
        'approval_items': [
          {
            'id': 'approval-email-draft-1',
            'kind': 'email_send_confirmation',
            'title': 'Weekly report',
            'email_draft_id': 'email-draft-1',
          },
        ],
      },
    });

    final calendarRun = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-2',
      'conversation_id': 'conversation-1',
      'assistant': {'role': 'assistant', 'content': '日历事件待确认。'},
      'metadata': {
        'run_id': 'run-2',
        'turn_id': 'turn-run-2',
        'conversation_id': 'conversation-1',
        'vault_id': 'vault-1',
        'response_type': 'calendar_event_candidate',
        'run_status': 'waiting_for_approval',
        'approval_required': true,
        'approval_items': [
          {
            'id': 'approval-calendar-event-1',
            'kind': 'calendar_event_confirmation',
            'title': 'Design review',
            'calendar_event_id': 'calendar-event-1',
          },
        ],
      },
    });

    expect(
        emailRun.metadata.approvalItems.single.emailDraftId, 'email-draft-1');
    expect(
      calendarRun.metadata.approvalItems.single.calendarEventId,
      'calendar-event-1',
    );
  });
}
