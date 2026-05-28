import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'third canonical Stitch screen renders reminder clarification approvals',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(_thirdScreenState());
      final sender = _ApprovalRecordingSender();

      await tester.binding.setSurfaceSize(const Size(780, 2436));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AppShell(
                    chatTabBuilder: (_, __) => AgentConversationPage(
                      conversation: const Conversation(
                        id: 'loop_home',
                        title: 'Loop',
                        createdAtMs: 0,
                        updatedAtMs: 0,
                      ),
                      isTabActive: true,
                      runtimeConversationSender: sender,
                      runtimeAgentStateRepository: repository,
                    ),
                    reviewTabBuilder: (_, __) => const SizedBox(),
                    notesTabBuilder: (_, __) => const SizedBox(),
                    memoryTabBuilder: (_, __) => const SizedBox(),
                    settingsTabBuilder: (_, __) => const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('May 12, 2026'), findsOneWidget);
      expect(find.text('每年孩子生日前一天提醒我买礼物。'), findsOneWidget);
      expect(find.text('我需要先知道孩子生日。'), findsOneWidget);
      expect(find.text('14:02'), findsNWidgets(2));
      expect(
        find.byKey(
          const ValueKey('agent_operating_pending_intent_pending-gift'),
        ),
        findsOneWidget,
      );
      expect(find.text('Pending Intent'), findsOneWidget);
      expect(find.text('ACTION HALTED'), findsOneWidget);
      expect(find.text('Missing Slot: child birthday'), findsOneWidget);
      expect(
        find.text("Calculation of 'day before' requires base date."),
        findsOneWidget,
      );

      expect(find.text('孩子生日是 2018 年 6 月 1 日。'), findsOneWidget);
      expect(find.text('我准备了两项候选，请确认。'), findsOneWidget);
      expect(find.text('Memory Candidate'), findsOneWidget);
      expect(find.text('FACT TO BE COMMITTED:'), findsOneWidget);
      expect(find.text('孩子生日是 6 月 1 日'), findsOneWidget);
      expect(find.text('Recurring Reminder Candidate'), findsOneWidget);
      expect(find.text('给孩子买生日礼物'), findsOneWidget);
      expect(find.text('Every year on May 31'), findsOneWidget);
      expect(find.text('May 31, 2027'), findsOneWidget);
      expect(
        find.text('No recurring reminder is active until approved.'),
        findsOneWidget,
      );
      expect(find.text('Active Reminder'), findsNothing);
      expect(
        find.text(
            AppLocale.en.translations.chat.agentConversation.composerHint),
        findsOneWidget,
      );
      expect(
          find.byKey(const ValueKey('app_shell_bottom_nav')), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_recurring_approve_approval-recurring-gift',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_recurring_edit_approval-recurring-gift',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_recurring_dismiss_approval-recurring-gift',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_recurring_edit_approval-recurring-gift',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey(
            'runtime_candidate_approval_title_field_approval-recurring-gift',
          ),
        ),
        '给孩子买生日礼物（已修改）',
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'runtime_candidate_approval_save_title_approval-recurring-gift',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.approvalPatches, [
        'approval-recurring-gift:1:给孩子买生日礼物（已修改）',
      ]);
      expect(find.text('给孩子买生日礼物（已修改）'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_recurring_approve_approval-recurring-gift',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('agent_operating_memory_approve_approval-memory-bday'),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-recurring-gift', 'approve'),
        ('uid_1', 'approval-memory-bday', 'approve'),
      ]);
    },
  );
}

RuntimeAgentState _thirdScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '每年孩子生日前一天提醒我买礼物。',
        'created_at_ms': 1778565720000,
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '我需要先知道孩子生日。',
        'created_at_ms': 1778565720000,
      },
      {
        'turn_id': 'turn-user-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '孩子生日是 2018 年 6 月 1 日。',
        'created_at_ms': 1778565900000,
      },
      {
        'turn_id': 'turn-assistant-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '我准备了两项候选，请确认。',
        'created_at_ms': 1778565900000,
      },
    ],
    'working_set_records': [
      {
        'id': 'pending-gift',
        'kind': 'pending_intent',
        'title': 'Buy birthday gift reminder',
        'status': 'action_halted',
        'status_label': 'Action Halted',
        'source_message_id': 'turn-assistant-1',
        'missing_slot': 'child birthday',
        'reasoning': "Calculation of 'day before' requires base date.",
        'created_at_ms': 1778565720000,
      }
    ],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [
      {
        'id': 'approval-memory-bday',
        'kind': 'memory_confirmation',
        'title': '孩子生日是 6 月 1 日',
        'reason': 'User supplied child birthday to complete reminder intent.',
        'record': {
          'text': '孩子生日是 6 月 1 日',
          'conflict_risk': 'Low',
          'audit_id': 'mem_2026_05_12',
        },
      },
      {
        'id': 'approval-recurring-gift',
        'kind': 'recurring_reminder_confirmation',
        'title': '给孩子买生日礼物',
        'recurring_rule_id': 'recurring-rule-child-birthday-gift',
        'editable_fields': ['title'],
        'version': 1,
        'record': {
          'id': 'recurring-rule-child-birthday-gift',
          'title': '给孩子买生日礼物',
          'schedule_label': 'Every year on May 31',
          'next_trigger_label': 'May 31, 2027',
          'risk_assessment': 'Low',
          'audit_id': 'rem_2026_05_12',
        },
      }
    ],
    'recent_entity_refs': [],
    'latest_context_snapshot': null,
    'audit_refs': [],
  });
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  const _FakeRuntimeAgentStateRepository(this.state);

  final RuntimeAgentState state;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return state;
  }
}

final class _ApprovalRecordingSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  final List<(String, String, String)> decisions = <(String, String, String)>[];
  final List<String> approvalPatches = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    throw StateError('send should not be used');
  }

  @override
  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals({
    required String vaultId,
  }) async {
    return const <SecretaryRuntimeApprovalItem>[];
  }

  @override
  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String approvalId,
    required String decision,
  }) async {
    decisions.add((vaultId, approvalId, decision));
    return null;
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) async {
    final title = '${changes['title']}';
    approvalPatches.add('$approvalId:$baseVersion:$title');
    return SecretaryRuntimeApprovalItem(
      id: approvalId,
      taskId: '',
      title: title,
      kind: 'recurring_reminder_confirmation',
      recurringRuleId: 'recurring-rule-child-birthday-gift',
      editableFields: const ['title'],
      version: baseVersion + 1,
      record: <String, Object?>{
        'id': 'recurring-rule-child-birthday-gift',
        'title': title,
        'schedule_label': 'Every year on May 31',
        'next_trigger_label': 'May 31, 2027',
        'risk_assessment': 'Low',
        'audit_id': 'rem_2026_05_12',
      },
    );
  }
}

final class _CloudAuthController extends ChangeNotifier
    implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
