import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:window_manager/window_manager.dart';

import '../test/test_backend.dart';
import '../test/test_i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('Stitch Screen 08 Manual QA');
  await windowManager.setMinimumSize(const Size(390, 720));
  await windowManager.setSize(const Size(780, 1100));
  await windowManager.center();

  runApp(
    wrapWithI18n(
      MaterialApp(
        debugShowCheckedModeBanner: false,
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
                chatTabBuilder: (_, __) => const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                  runtimeConversationSender: _EmailUnauthorizedSender(),
                  runtimeAgentStateRepository:
                      _EmailUnauthorizedRuntimeAgentStateRepository(),
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
  const _EmailUnauthorizedRuntimeAgentStateRepository();

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
