import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'managed pro recurring approval card edits title before approval',
    (tester) async {
      final sender = _PatchableRuntimeSender(
        pendingResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-recurring-pending',
          'conversation_id': 'loop_home',
          'assistant': {'content': '待确认生日提醒。'},
          'metadata': {
            'run_id': 'run-recurring-pending',
            'turn_id': 'turn-recurring-pending',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'recurring_reminder_candidate',
            'run_status': 'waiting_for_approval',
            'approval_required': true,
            'applied_mutations': [],
            'approval_items': [
              {
                'id': 'approval-recurring-rule-child-birthday-gift',
                'title': '孩子生日',
                'kind': 'recurring_reminder_confirmation',
                'recurring_rule_id': 'recurring-rule-child-birthday-gift',
                'editable_fields': ['title'],
                'version': 1,
                'record': {
                  'id': 'recurring-rule-child-birthday-gift',
                  'title': '孩子生日',
                },
              },
            ],
          },
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapPage(sender));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '每年孩子生日前一天提醒我买礼物。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('孩子生日'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'runtime_candidate_approval_edit_title_'
            'approval-recurring-rule-child-birthday-gift',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(
          const ValueKey(
            'runtime_candidate_approval_title_field_'
            'approval-recurring-rule-child-birthday-gift',
          ),
        ),
        '给孩子买生日礼物',
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'runtime_candidate_approval_save_title_'
            'approval-recurring-rule-child-birthday-gift',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.approvalPatches, [
        'approval-recurring-rule-child-birthday-gift:1:给孩子买生日礼物',
      ]);
      expect(find.text('给孩子买生日礼物'), findsOneWidget);
    },
  );
}

Widget _wrapPage(_PatchableRuntimeSender sender) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: TestAppBackend(),
        child: AppPlatformCapabilityScope(
          capabilities: const AppPlatformCapabilities(
            supportsDesktopHotkey: true,
            supportsBiometricUnlock: false,
            supportsAudioRecording: true,
            supportsDesktopDrop: true,
            supportsDesktopBootSettings: true,
            supportsCameraCapture: false,
            usesCloudSessionModel: false,
          ),
          child: CloudAuthScope(
            controller: _CloudAuthController(),
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.example.test',
              modelName: 'cloud',
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SubscriptionScope(
                controller:
                    _SubscriptionController(SubscriptionStatus.entitled),
                child: AgentConversationPage(
                  conversation: const Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                  runtimeConversationSender: sender,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _PatchableRuntimeSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  _PatchableRuntimeSender({required this.pendingResult});

  final SecretaryRuntimeConversationResult pendingResult;
  final List<String> approvalPatches = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    return pendingResult;
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
      },
    );
  }
}

final class _SubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _SubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
}

final class _CloudAuthController implements CloudAuthController {
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
