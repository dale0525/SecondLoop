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
    'tenth canonical Stitch screen renders local computer refusal',
    (tester) async {
      await _pumpTenthScreen(
        tester: tester,
        size: const Size(780, 2264),
        repository: _LocalComputerSafetyRuntimeAgentStateRepository(),
        sender: const _LocalComputerSafetySender(),
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('Local Operation Blocked'), findsOneWidget);
      expect(
        find.text('帮我打开终端执行 rm -rf ~/Downloads/test。'),
        findsOneWidget,
      );
      expect(
        find.text(
          'I cannot execute terminal commands or modify local files. No '
          'action was taken.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Security Protocol: Local Computer Operation Refusal (Approved)',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_local_safety_refusal_safety-local-block-0612',
          ),
        ),
        findsOneWidget,
      );

      expect(find.text('SAFETY PROTOCOL'), findsOneWidget);
      expect(find.text('No command executed'), findsOneWidget);
      expect(find.text('No local file access'), findsOneWidget);
      expect(find.text('No terminal automation'), findsOneWidget);
      expect(find.text('Manual review recommended'), findsOneWidget);

      expect(find.text('ALTERNATIVE ACTION'), findsOneWidget);
      expect(find.text('Downloads cleanup checklist'), findsOneWidget);
      expect(
        find.text('Open Finder and navigate to Downloads'),
        findsOneWidget,
      );
      expect(find.text("Locate the folder named 'test'"), findsOneWidget);
      expect(find.text('Review contents before deletion'), findsOneWidget);
      expect(find.text('Save to Vault'), findsOneWidget);

      expect(find.text('AUDIT & SAFETY'), findsOneWidget);
      expect(find.text('SEC-2026-0612'), findsOneWidget);
      expect(find.text('Skill'), findsOneWidget);
      expect(find.text('local-computer-safety'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('refused / no side effect'), findsOneWidget);
      expect(find.text('Blocked Action'), findsOneWidget);
      expect(find.text('shell execution'), findsOneWidget);
      expect(find.text('Source ID'), findsOneWidget);
      expect(find.text('MSG-88291'), findsOneWidget);
      expect(find.text('Tool Trace'), findsOneWidget);
      expect(find.text('safety-check-v2'), findsOneWidget);

      expect(find.text('Blocked External Transaction'), findsNothing);
      expect(find.textContaining('Command succeeded'), findsNothing);
      expect(find.textContaining('Terminal opened'), findsNothing);
      expect(find.textContaining('Deleted ~/Downloads/test'), findsNothing);
    },
  );

  testWidgets(
    'save to vault prepares a manual checklist without local side effects',
    (tester) async {
      await _pumpTenthScreen(
        tester: tester,
        size: const Size(780, 2264),
        repository: _LocalComputerSafetyRuntimeAgentStateRepository(),
        sender: const _LocalComputerSafetySender(),
      );

      await tester.ensureVisible(
        find.byKey(
          const ValueKey(
            'agent_operating_local_safety_save_safety-local-block-0612',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_local_safety_save_safety-local-block-0612',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Safe follow-up prepared'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Create a vault note draft with this manual'),
        findsOneWidget,
      );
      expect(find.textContaining('Do not execute terminal commands'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('chat_send')), findsOneWidget);
    },
  );

  testWidgets(
    'local computer refusal remains stable across responsive widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1700),
        Size(780, 2264),
        Size(1180, 1500),
      ];
      for (final size in sizes) {
        await _pumpTenthScreen(
          tester: tester,
          size: size,
          repository: _LocalComputerSafetyRuntimeAgentStateRepository(),
          sender: const _LocalComputerSafetySender(),
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_local_safety_refusal_safety-local-block-0612',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Security Protocol: Local Computer Operation Refusal (Approved)',
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_local_safety_protocol_safety-local-block-0612',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No terminal automation'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_local_safety_alternative_safety-local-block-0612',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_local_safety_save_safety-local-block-0612',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_local_safety_metadata_safety-local-block-0612',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('refused / no side effect'), findsOneWidget);
        expect(find.text('safety-check-v2'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'screen width $size');
      }
    },
  );
}

Future<void> _pumpTenthScreen({
  required WidgetTester tester,
  required Size size,
  required _LocalComputerSafetyRuntimeAgentStateRepository repository,
  required _LocalComputerSafetySender sender,
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

RuntimeAgentState _tenthScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-local-computer',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我打开终端执行 rm -rf ~/Downloads/test。',
        'created_at_ms': 1782057720000,
      },
      {
        'turn_id': 'turn-assistant-local-computer',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            'I cannot execute terminal commands or modify local files. No '
                'action was taken.',
        'created_at_ms': 1782057720000,
      },
    ],
    'working_set_records': [
      {
        'id': 'safety-local-block-0612',
        'kind': 'external_side_effect_blocked',
        'skill': 'local-computer-safety',
        'blocked_action': 'shell execution',
        'status': 'refused',
        'status_label': 'refused / no side effect',
        'audit_id': 'SEC-2026-0612',
        'source_id': 'MSG-88291',
        'source_message_id': 'turn-user-local-computer',
        'assistant_turn_id': 'turn-assistant-local-computer',
        'tool_trace': 'safety-check-v2',
      },
    ],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [],
    'recent_entity_refs': [],
    'latest_context_snapshot': {
      'id': 'CTX-SAFE-0612',
      'generated_at_ms': 1782057720000,
      'packet': {
        'runtime_skill': 'local-computer-safety',
        'external_side_effect_blocked': true,
      },
    },
    'audit_refs': [
      {'id': 'SEC-2026-0612'},
    ],
  });
}

final class _LocalComputerSafetyRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _tenthScreenState();
  }
}

final class _LocalComputerSafetySender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  const _LocalComputerSafetySender();

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    throw StateError('safe checklist action should only prepare a prompt');
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
    throw StateError('local computer refusal has no approval path');
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('local computer refusal has no editable approval');
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
