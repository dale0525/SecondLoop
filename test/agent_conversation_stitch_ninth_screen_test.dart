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
    'ninth canonical Stitch screen renders purchase payment refusal',
    (tester) async {
      await _pumpNinthScreen(
        tester: tester,
        size: const Size(780, 2182),
        repository: _PurchasePaymentSafetyRuntimeAgentStateRepository(),
        sender: const _PurchasePaymentSafetySender(),
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('Blocked External Transaction'), findsOneWidget);
      expect(find.text('帮我直接买两张明天去上海的高铁票并付款。'), findsOneWidget);
      expect(find.text('Security Protocol Active'), findsOneWidget);
      expect(
        find.text(
          'I cannot execute direct purchases or financial payments on your '
          'behalf. My operational scope is restricted to information '
          'management and organizational tasks to ensure your financial '
          'security. No transaction has been initiated.',
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_safety_refusal_safety-purchase-block-042',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Safe Alternatives'), findsOneWidget);
      expect(find.text('3 Actions Available'), findsOneWidget);
      expect(find.text('Research train options'), findsOneWidget);
      expect(find.text('Find schedule and availability'), findsOneWidget);
      expect(find.text('Create booking checklist'), findsOneWidget);
      expect(find.text('Prepare required passenger details'), findsOneWidget);
      expect(find.text('Set reminder for manual booking'), findsOneWidget);
      expect(find.text('Alert for manual ticket release'), findsOneWidget);

      expect(find.text('TRANSACTION SAFETY PROTOCOL'), findsOneWidget);
      expect(find.text('Skill'), findsOneWidget);
      expect(find.text('purchase-payment-safety'), findsOneWidget);
      expect(find.text('Blocked Action'), findsOneWidget);
      expect(find.text('ticket purchase + payment'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Refused / No external action'), findsOneWidget);
      expect(find.text('Audit ID'), findsOneWidget);
      expect(find.text('aud-sec-7729'), findsOneWidget);
      expect(find.text('Source ID'), findsOneWidget);
      expect(find.text('msg-usr-042'), findsOneWidget);
      expect(find.text('Tool Trace'), findsOneWidget);
      expect(find.text('safe-check-v2'), findsOneWidget);
      expect(find.text('Email Blocked: Authorization Required'), findsNothing);

      expect(find.text('Ticket Purchased'), findsNothing);
      expect(find.text('Payment Complete'), findsNothing);
      expect(find.text('Purchase approved'), findsNothing);
      expect(find.textContaining('已付款'), findsNothing);
      expect(find.textContaining('已购票'), findsNothing);
    },
  );

  testWidgets(
    'safe alternatives prepare follow-up prompts without transaction side effects',
    (tester) async {
      await _pumpNinthScreen(
        tester: tester,
        size: const Size(780, 2182),
        repository: _PurchasePaymentSafetyRuntimeAgentStateRepository(),
        sender: const _PurchasePaymentSafetySender(),
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_safety_research_safety-purchase-block-042',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Safe follow-up prepared'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Research tomorrow train options to Shanghai'),
        findsOneWidget,
      );
      expect(find.textContaining('Do not book or pay.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_send')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'purchase payment refusal remains stable across responsive widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1700),
        Size(780, 2182),
        Size(1180, 1500),
      ];
      for (final size in sizes) {
        await _pumpNinthScreen(
          tester: tester,
          size: size,
          repository: _PurchasePaymentSafetyRuntimeAgentStateRepository(),
          sender: const _PurchasePaymentSafetySender(),
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_safety_refusal_safety-purchase-block-042',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Security Protocol Active'), findsOneWidget);
        expect(find.text('No transaction has been initiated.'), findsNothing);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_safety_alternatives_safety-purchase-block-042',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Safe Alternatives'), findsOneWidget);
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_safety_checklist_safety-purchase-block-042',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_safety_metadata_safety-purchase-block-042',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Refused / No external action'), findsOneWidget);
        expect(find.text('safe-check-v2'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'screen width $size');
      }
    },
  );
}

Future<void> _pumpNinthScreen({
  required WidgetTester tester,
  required Size size,
  required _PurchasePaymentSafetyRuntimeAgentStateRepository repository,
  required _PurchasePaymentSafetySender sender,
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

RuntimeAgentState _ninthScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-purchase',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我直接买两张明天去上海的高铁票并付款。',
        'created_at_ms': 1782057600000,
      },
      {
        'turn_id': 'turn-assistant-purchase',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            'I cannot execute direct purchases or financial payments on your '
                'behalf. My operational scope is restricted to information '
                'management and organizational tasks to ensure your financial '
                'security. No transaction has been initiated.',
        'created_at_ms': 1782057660000,
      },
    ],
    'working_set_records': [
      {
        'id': 'safety-purchase-block-042',
        'kind': 'external_side_effect_blocked',
        'skill': 'purchase-payment-safety',
        'blocked_action': 'ticket purchase + payment',
        'status': 'external_side_effect_blocked',
        'status_label': 'Refused / No external action',
        'audit_id': 'aud-sec-7729',
        'source_id': 'msg-usr-042',
        'source_message_id': 'turn-user-purchase',
        'assistant_turn_id': 'turn-assistant-purchase',
        'tool_trace': 'safe-check-v2',
      },
    ],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [],
    'recent_entity_refs': [],
    'latest_context_snapshot': {
      'id': 'CTX-SAFE-0524',
      'generated_at_ms': 1782057660000,
      'packet': {
        'runtime_skill': 'purchase-payment-safety',
        'external_side_effect_blocked': true,
      },
    },
    'audit_refs': [
      {'id': 'aud-sec-7729'},
    ],
  });
}

final class _PurchasePaymentSafetyRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _ninthScreenState();
  }
}

final class _PurchasePaymentSafetySender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  const _PurchasePaymentSafetySender();

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    throw StateError('safe alternatives should only prepare follow-up prompts');
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
    throw StateError('purchase payment refusal has no approval path');
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('purchase payment refusal has no editable approval');
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
