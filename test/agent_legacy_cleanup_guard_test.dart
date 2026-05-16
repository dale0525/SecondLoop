import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'legacy local semantic actions and task hub product surfaces are removed',
      () {
    const removedPaths = <String>[
      'lib/core/ai/local_semantic_parse_result.dart',
      'lib/core/ai/local_semantic_parser.dart',
      'lib/core/ai/semantic_parse_auto_actions_gate.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner_client.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner_models.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner_parse_policy.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner_store.dart',
      'lib/core/ai/semantic_parse_auto_actions_runner_todo_commands.dart',
      'lib/core/ai/semantic_parse_edit_policy.dart',
      'lib/core/secretary/local_todo_command_parser.dart',
      'lib/features/actions/agenda/todo_agenda_page.dart',
      'lib/features/actions/todo/message_auto_actions_queue.dart',
      'lib/features/actions/todo/message_action_resolver.dart',
      'lib/features/actions/todo/todo_detail_page.dart',
      'lib/features/actions/todo/todo_detail_page_attachment_picker.dart',
      'lib/features/actions/todo/todo_detail_page_checklist.dart',
      'lib/features/actions/todo/todo_detail_page_checklist_suggestions.dart',
      'lib/features/actions/todo/todo_detail_page_composer.dart',
      'lib/features/actions/todo/todo_detail_page_due_chip.dart',
      'lib/features/actions/todo/todo_detail_page_followup_suggestions.dart',
      'lib/features/actions/todo/todo_detail_page_message_actions.dart',
      'lib/features/actions/todo/todo_detail_page_recurring_series.dart',
      'lib/features/actions/todo/todo_detail_page_send.dart',
      'lib/features/actions/todo/todo_detail_page_status_widgets.dart',
      'lib/features/chat/semantic_parse_job_status_row.dart',
      'lib/features/actions/task_hub',
      'test/message_auto_actions_queue_test.dart',
      'test/support/review_reminder_notification_scheduler_test_fakes.dart',
      'test/semantic_parse_job_status_row_test.dart',
      'test/semantic_parse_job_status_row_init_state_test.dart',
      'test/semantic_parse_edit_policy_test.dart',
      'test/task_hub_localization_test.dart',
      'test/task_hub_quick_actions_test_helpers.dart',
    ];

    for (final path in removedPaths) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: '$path should not remain in the Agent-first product surface.',
      );
    }

    final appSource = File('lib/app/app.dart').readAsStringSync();
    expect(appSource, isNot(contains('SemanticParseAutoActionsGate')));

    final actionsEn = File('lib/i18n/actions_en.i18n.json').readAsStringSync();
    final actionsZh =
        File('lib/i18n/actions_zh_CN.i18n.json').readAsStringSync();
    expect(actionsEn, isNot(contains('"taskHub"')));
    expect(actionsZh, isNot(contains('"taskHub"')));
    expect(actionsEn, isNot(contains('"todoDetail"')));
    expect(actionsZh, isNot(contains('"todoDetail"')));
  });
}
