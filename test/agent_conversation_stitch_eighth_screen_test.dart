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

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'eighth canonical Stitch screen renders unauthorized email as draft only',
    (tester) async {
      final repository = _EmailUnauthorizedRuntimeAgentStateRepository();

      await _pumpEighthScreen(
        tester: tester,
        size: const Size(780, 2112),
        repository: repository,
        sender: const _EmailUnauthorizedSender(),
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('Email Not Connected'), findsOneWidget);
      expect(find.text('直接把周报邮件发给 Alice。'), findsOneWidget);
      expect(
        find.text(
          '我目前无法发送邮件，因为您的 Email 服务尚未连接。我可以先为您准备草稿，建议您连接 Google Workspace 以启用自动发送。',
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey('agent_operating_email_draft_draft-weekly-report'),
        ),
        findsOneWidget,
      );
      expect(find.text('Email Draft'), findsOneWidget);
      expect(find.text('Draft: Weekly Report'), findsOneWidget);
      expect(find.text('Draft Only'), findsOneWidget);
      expect(find.text('To:'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Subject:'), findsOneWidget);
      expect(find.text('周报'), findsOneWidget);
      expect(find.text('Body:'), findsOneWidget);
      expect(find.text('附件是本周的工作汇报，请查收。'), findsOneWidget);
      expect(find.text('Source: Chat Message'), findsOneWidget);
      expect(find.text('Audit: draft_2026_05_22'), findsOneWidget);
      expect(find.text('SAVE DRAFT'), findsOneWidget);
      expect(find.text('CONNECT EMAIL'), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey('agent_operating_email_guardrail_email-block-txn-042'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Email Blocked: Authorization Required'),
        findsOneWidget,
      );
      expect(find.text('Reason:'), findsOneWidget);
      expect(find.text('Needs Configuration'), findsOneWidget);
      expect(find.text('Connector:'), findsOneWidget);
      expect(find.text('Google Workspace (Disconnected)'), findsOneWidget);
      expect(find.text('Action:'), findsOneWidget);
      expect(find.text('Send Email (Blocked)'), findsOneWidget);
      expect(find.text('Status:'), findsOneWidget);
      expect(find.text('Not Executed (Fail Closed)'), findsOneWidget);
      expect(find.text('Risk: Low'), findsOneWidget);
      expect(find.text('Audit: TXN-2026-05-22-042'), findsOneWidget);
      expect(find.text('tool: email.send'), findsOneWidget);
      expect(find.text('Entity Ref:'), findsNothing);
      expect(find.text('Email Sent'), findsNothing);
    },
  );

  testWidgets(
    'email unauthorized screen keeps draft-only guardrails across widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1700),
        Size(780, 2112),
        Size(1180, 1500),
      ];
      for (final size in sizes) {
        await _pumpEighthScreen(
          tester: tester,
          size: size,
          repository: _EmailUnauthorizedRuntimeAgentStateRepository(),
          sender: const _EmailUnauthorizedSender(),
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey('agent_operating_email_draft_draft-weekly-report'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Draft: Weekly Report'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('周报'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_email_guardrail_email-block-txn-042',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Email Blocked: Authorization Required'),
          findsOneWidget,
          reason: 'screen width ${size.width}',
        );
        expect(find.text('Not Executed (Fail Closed)'), findsOneWidget);
        expect(find.text('tool: email.send'), findsOneWidget);
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_email_save_draft-weekly-report',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_email_connect_draft-weekly-report',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'screen width $size');
      }
    },
  );
}

Future<void> _pumpEighthScreen({
  required WidgetTester tester,
  required Size size,
  required _EmailUnauthorizedRuntimeAgentStateRepository repository,
  required _EmailUnauthorizedSender sender,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
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
}

RuntimeAgentState _eighthScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-email',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '直接把周报邮件发给 Alice。',
        'created_at_ms': 1782057600000,
      },
      {
        'turn_id': 'turn-assistant-email',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            '我目前无法发送邮件，因为您的 Email 服务尚未连接。我可以先为您准备草稿，建议您连接 Google Workspace 以启用自动发送。',
        'created_at_ms': 1782057660000,
      },
    ],
    'working_set_records': [
      {
        'id': 'draft-weekly-report',
        'kind': 'email_draft',
        'title': 'Draft: Weekly Report',
        'to': 'Alice',
        'subject': '周报',
        'body': '附件是本周的工作汇报，请查收。',
        'source': 'Chat Message',
        'audit_id': 'draft_2026_05_22',
        'draft_id': 'draft_2026_05_22',
        'connector_status': 'needs_configuration',
        'source_message_id': 'turn-user-email',
        'assistant_turn_id': 'turn-assistant-email',
      },
      {
        'id': 'email-block-txn-042',
        'kind': 'external_tool_block',
        'reason': 'Needs Configuration',
        'connector': 'Google Workspace (Disconnected)',
        'blocked_action': 'Send Email (Blocked)',
        'status': 'not_executed',
        'status_label': 'Not Executed (Fail Closed)',
        'risk': 'Low',
        'audit_id': 'TXN-2026-05-22-042',
        'tool': 'email.send',
        'source_message_id': 'turn-user-email',
        'assistant_turn_id': 'turn-assistant-email',
      },
    ],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [],
    'recent_entity_refs': [
      {
        'entity_id': 'draft-weekly-report',
        'kind': 'email_draft',
        'label': 'Draft: Weekly Report',
      },
    ],
    'latest_context_snapshot': {
      'id': 'CTX-EMAIL-0522',
      'generated_at_ms': 1782057660000,
      'packet': {
        'runtime_tool': 'email.send',
        'connector_status': 'needs_configuration',
      },
    },
    'audit_refs': [
      {'id': 'TXN-2026-05-22-042'},
    ],
  });
}

final class _EmailUnauthorizedRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _eighthScreenState();
  }
}

final class _EmailUnauthorizedSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  const _EmailUnauthorizedSender();

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
  }) {
    throw StateError('email unauthorized flow has no send approval');
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('email unauthorized flow has no editable approval');
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
