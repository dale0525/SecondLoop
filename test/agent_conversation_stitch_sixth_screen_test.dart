import 'dart:convert';

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
    'sixth canonical Stitch screen renders OCR media result from runtime state',
    (tester) async {
      final repository = _FileOcrRuntimeAgentStateRepository();
      final sender = _FileOcrApprovalRecordingSender(repository);

      await _pumpSixthScreen(
        tester: tester,
        size: const Size(780, 2184),
        repository: repository,
        sender: sender,
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('Vault Upload'), findsOneWidget);
      expect(
        find.text('帮我看看这张图片里写了什么，顺便总结一下。'),
        findsOneWidget,
      );
      expect(find.text('qa-ocr-sample.png'), findsWidgets);
      expect(find.text('2.4 MB'), findsOneWidget);
      expect(find.text('ocr'), findsOneWidget);
      expect(find.text('summarize'), findsOneWidget);
      expect(find.text('source synced to Vault'), findsOneWidget);
      expect(
        find.text(
          "I've processed the image. Here is the extracted text and a summary.",
        ),
        findsOneWidget,
      );

      final attachmentChip = find.byKey(
        const ValueKey('agent_message_attachment_chip_att-qa-media'),
      );
      expect(attachmentChip, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('agent_message_attachment_image_att-qa-media'),
        ),
        findsOneWidget,
      );

      await tester.tap(attachmentChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attachment_image_preview_surface')),
        findsOneWidget,
      );
      expect(find.textContaining('Codec failed'), findsNothing);
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('attachment_image_preview_surface')),
        ),
      ).pop();
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('agent_assistant_media_results_turn-assistant-ocr'),
        ),
        findsOneWidget,
      );
      expect(find.text('Media Result'), findsOneWidget);
      expect(find.text('OCR TEXT'), findsOneWidget);
      expect(find.text('QA MEDIA'), findsOneWidget);
      expect(find.text('SUMMARY'), findsOneWidget);
      expect(
        find.text(
            'High-fidelity document scan containing operational test data.'),
        findsOneWidget,
      );
      expect(find.text('Source ID:'), findsOneWidget);
      expect(find.text('ATT-2026-0523-001'), findsOneWidget);
      expect(find.text('Confidence:'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('Saved to Vault:'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_reminder_candidate_approval-qa-media-followup',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Reminder Candidate'), findsOneWidget);
      expect(find.text('Follow up on QA Media'), findsOneWidget);
      expect(
        find.text('Create a reminder to review extraction result tomorrow.'),
        findsOneWidget,
      );
      expect(find.text('Pending Approval'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey(
            'agent_operating_reminder_approve_approval-qa-media-followup',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_reminder_approve_approval-qa-media-followup',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-qa-media-followup', 'approve'),
      ]);
      expect(
        find.byKey(
          const ValueKey(
            'agent_operating_reminder_candidate_approval-qa-media-followup',
          ),
        ),
        findsNothing,
      );
      expect(find.text('QA MEDIA'), findsOneWidget);
    },
  );

  testWidgets(
    'file OCR screen keeps required evidence across widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1800),
        Size(780, 2184),
        Size(1180, 1600),
      ];
      for (final size in sizes) {
        final repository = _FileOcrRuntimeAgentStateRepository();
        await _pumpSixthScreen(
          tester: tester,
          size: size,
          repository: repository,
          sender: _FileOcrApprovalRecordingSender(repository),
        );

        expect(find.text('qa-ocr-sample.png'), findsWidgets);
        expect(find.text('OCR TEXT'), findsOneWidget);
        expect(find.text('QA MEDIA'), findsOneWidget);
        expect(find.text('ATT-2026-0523-001'), findsOneWidget);
        expect(find.text('Follow up on QA Media'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_reminder_approve_approval-qa-media-followup',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_reminder_approve_approval-qa-media-followup',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_reminder_dismiss_approval-qa-media-followup',
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

Future<void> _pumpSixthScreen({
  required WidgetTester tester,
  required Size size,
  required _FileOcrRuntimeAgentStateRepository repository,
  required _FileOcrApprovalRecordingSender sender,
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

RuntimeAgentState _sixthScreenState({required bool reminderApproved}) {
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': const [
      {
        'turn_id': 'turn-user-ocr',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我看看这张图片里写了什么，顺便总结一下。',
        'created_at_ms': 1779494400000,
        'attachment_refs': ['att-qa-media'],
        'attachments': [
          {
            'id': 'att-qa-media',
            'attachment_id': 'att-qa-media',
            'filename': 'qa-ocr-sample.png',
            'mime_type': 'image/png',
            'media_type': 'image',
            'size_label': '2.4 MB',
          },
        ],
      },
      {
        'turn_id': 'turn-assistant-ocr',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            "I've processed the image. Here is the extracted text and a summary.",
        'created_at_ms': 1779494460000,
      },
    ],
    'working_set_records': const [
      {
        'id': 'media-result-att-qa-media',
        'kind': 'media_result',
        'assistant_turn_id': 'turn-assistant-ocr',
        'source_message_id': 'turn-user-ocr',
        'attachment_id': 'att-qa-media',
        'source_id': 'ATT-2026-0523-001',
        'filename': 'qa-ocr-sample.png',
        'media_type': 'image',
        'ocr_text': 'QA MEDIA',
        'summary':
            'High-fidelity document scan containing operational test data.',
        'confidence_percent': 98,
        'saved_to_vault': true,
        'status': 'vault_synced',
        'citations': [
          {'title': 'qa-ocr-sample.png'},
        ],
      },
    ],
    'tasks': const [],
    'memory_records': const [],
    'recurring_reminder_rules': const [],
    'approval_items': [
      if (!reminderApproved)
        const {
          'id': 'approval-qa-media-followup',
          'kind': 'reminder_confirmation',
          'title': 'Follow up on QA Media',
          'reason': 'Create a reminder to review extraction result tomorrow.',
          'record': {
            'title': 'Follow up on QA Media',
            'description':
                'Create a reminder to review extraction result tomorrow.',
            'due_label': 'Tomorrow',
            'source': 'media-result-att-qa-media',
            'source_id': 'ATT-2026-0523-001',
            'approval_status': 'pending',
          },
        },
    ],
    'recent_entity_refs': const [
      {
        'entity_id': 'att-qa-media',
        'kind': 'attachment',
        'label': 'qa-ocr-sample.png',
      },
    ],
    'latest_context_snapshot': const {
      'id': 'CTX-MEDIA-0523',
      'generated_at_ms': 1779494460000,
      'packet': {
        'working_set': {
          'records': [],
        },
      },
    },
    'audit_refs': const [
      {'id': 'ATT-2026-0523-001'},
    ],
  });
}

final class _FileOcrRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  bool reminderApproved = false;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _sixthScreenState(reminderApproved: reminderApproved);
  }
}

final class _FileOcrApprovalRecordingSender
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeApprovalSender,
        ChatRuntimeAttachmentContentFetcher {
  _FileOcrApprovalRecordingSender(this.repository);

  final _FileOcrRuntimeAgentStateRepository repository;
  final List<(String, String, String)> decisions = <(String, String, String)>[];

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
    if (approvalId == 'approval-qa-media-followup' && decision == 'approve') {
      repository.reminderApproved = true;
    }
    return null;
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('reminder edit should not be used');
  }

  @override
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  }) async {
    return attachmentId == 'att-qa-media' ? _tinyPngBytes() : null;
  }
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAO0lEQVR4nO3OsQ0AEBAAwF/GZMaXKDRKhhB5kiuuv+hjrkwhICDwfKDUdkRAQEBAQEDg/8BtAgIC6YENCNz0xDRpq1MAAAAASUVORK5CYII=';
  return Uint8List.fromList(base64Decode(b64));
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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
