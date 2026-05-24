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
    'seventh canonical Stitch screen renders meeting audio candidates from runtime state',
    (tester) async {
      final repository = _MeetingAudioRuntimeAgentStateRepository();
      final sender = _MeetingAudioApprovalRecordingSender(repository);

      await _pumpSeventhScreen(
        tester: tester,
        size: const Size(780, 2630),
        repository: repository,
        sender: sender,
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('Vault Upload'), findsOneWidget);
      expect(
        find.text(
          'Process the audio recording from the Q3 Planning Sync and extract key actions.',
        ),
        findsOneWidget,
      );
      expect(find.text('q3_planning_sync_raw.m4a'), findsWidgets);
      expect(find.text('45:12 • 42 MB'), findsOneWidget);
      expect(
        find.byKey(
            const ValueKey('agent_message_attachment_audio_att-q3-sync')),
        findsOneWidget,
      );
      expect(find.text('audio-transcription'), findsOneWidget);
      expect(find.text('meeting-minutes'), findsOneWidget);
      expect(find.text('High-fidelity processing confirmed'), findsOneWidget);
      expect(
        find.text(
          "I've processed the recording. Here is the structured summary and the proposed action items.",
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey('agent_assistant_media_results_turn-assistant-audio'),
        ),
        findsOneWidget,
      );
      expect(find.text('Meeting Audio Result'), findsOneWidget);
      expect(find.text('Meeting Summary'), findsOneWidget);
      expect(find.text('Meeting ID:'), findsOneWidget);
      expect(find.text('MTG-Q3-2026-001'), findsWidgets);
      expect(find.text('Duration:'), findsOneWidget);
      expect(find.text('Transcript'), findsOneWidget);
      expect(find.text('Meeting minutes'), findsOneWidget);
      expect(find.text('Decisions'), findsOneWidget);
      expect(find.text('Action items'), findsOneWidget);
      expect(find.text('Saved to Vault:'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      for (final approvalId in const [
        'approval-action-act091',
        'approval-action-act092',
        'approval-action-act093',
      ]) {
        expect(
          find.byKey(ValueKey('agent_operating_action_candidate_$approvalId')),
          findsOneWidget,
        );
      }
      expect(find.text('ACT-091'), findsOneWidget);
      expect(find.text('ACT-092'), findsOneWidget);
      expect(find.text('ACT-093'), findsOneWidget);
      expect(
        find.text('Draft phased rollout schedule for Vault feature'),
        findsWidgets,
      );
      expect(find.text('Finalize budget allocation for teaser campaign'),
          findsWidgets);
      expect(find.text('Schedule follow-up design review for Vault UI'),
          findsWidgets);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey(
            'agent_operating_action_candidate_create_approval-action-act091',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_action_candidate_create_approval-action-act091',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-action-act091', 'approve'),
      ]);
      expect(
        find.byKey(
          const ValueKey(
              'agent_operating_action_candidate_approval-action-act091'),
        ),
        findsNothing,
      );
      expect(find.text('MTG-Q3-2026-001'), findsWidgets);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey(
            'agent_operating_action_candidate_dismiss_approval-action-act092',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'agent_operating_action_candidate_dismiss_approval-action-act092',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-action-act091', 'approve'),
        ('uid_1', 'approval-action-act092', 'reject'),
      ]);
      expect(
        find.byKey(
          const ValueKey(
              'agent_operating_action_candidate_approval-action-act092'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'meeting audio screen keeps required evidence across widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1800),
        Size(780, 2630),
        Size(1180, 1600),
      ];
      for (final size in sizes) {
        final repository = _MeetingAudioRuntimeAgentStateRepository();
        await _pumpSeventhScreen(
          tester: tester,
          size: size,
          repository: repository,
          sender: _MeetingAudioApprovalRecordingSender(repository),
        );

        final messageList =
            find.byKey(const ValueKey('agent_operating_message_list'));
        if (messageList.evaluate().isNotEmpty) {
          final scrollable = find
              .descendant(
                of: messageList,
                matching: find.byType(Scrollable),
              )
              .first;
          final state = tester.state<ScrollableState>(scrollable);
          state.position.jumpTo(state.position.minScrollExtent);
          await tester.pump();
        }
        expect(find.text('q3_planning_sync_raw.m4a'), findsWidgets);
        expect(
          find.text('45:12 • 42 MB'),
          findsOneWidget,
          reason: 'screen width $size',
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_assistant_media_results_turn-assistant-audio',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Meeting Audio Result'), findsOneWidget);
        expect(find.text('MTG-Q3-2026-001'), findsWidgets);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_action_candidate_approval-action-act093',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Action Item Candidate'), findsNWidgets(3));

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'agent_operating_action_candidate_create_approval-action-act093',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_action_candidate_create_approval-action-act093',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(
                const ValueKey(
                  'agent_operating_action_candidate_dismiss_approval-action-act093',
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

Future<void> _pumpSeventhScreen({
  required WidgetTester tester,
  required Size size,
  required _MeetingAudioRuntimeAgentStateRepository repository,
  required _MeetingAudioApprovalRecordingSender sender,
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

RuntimeAgentState _seventhScreenState({
  required Set<String> resolvedApprovalIds,
}) {
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': const [
      {
        'turn_id': 'turn-user-audio',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content':
            'Process the audio recording from the Q3 Planning Sync and extract key actions.',
        'created_at_ms': 1785758400000,
        'attachment_refs': ['att-q3-sync'],
        'attachments': [
          {
            'id': 'att-q3-sync',
            'attachment_id': 'att-q3-sync',
            'filename': 'q3_planning_sync_raw.m4a',
            'mime_type': 'audio/mp4',
            'media_type': 'audio',
            'duration_label': '45:12',
            'size_label': '42 MB',
          },
        ],
      },
      {
        'turn_id': 'turn-assistant-audio',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            "I've processed the recording. Here is the structured summary and the proposed action items.",
        'created_at_ms': 1785758460000,
      },
    ],
    'working_set_records': const [
      {
        'id': 'media-result-q3-sync',
        'kind': 'media_result',
        'assistant_turn_id': 'turn-assistant-audio',
        'source_message_id': 'turn-user-audio',
        'attachment_id': 'att-q3-sync',
        'source_id': 'att-q3-sync',
        'meeting_id': 'MTG-Q3-2026-001',
        'filename': 'Meeting Summary',
        'media_type': 'audio',
        'duration_label': '45:12',
        'transcript':
            'Jordan confirmed the Vault rollout needs a phased schedule. Priya noted the teaser campaign budget must be finalized before launch planning.',
        'meeting_summary':
            'Summary of the Q3 Planning Sync discussing Vault rollout and marketing campaigns. Analysis performed on the full 45-minute transcript.',
        'decisions': [
          'Keep the Vault rollout phased so support can monitor sync quality.',
          'Hold the teaser campaign budget until finance signs off.',
        ],
        'action_items': [
          {
            'title': 'Draft phased rollout schedule for Vault feature',
            'owner': 'Maya',
            'due': 'Aug 5, 2026',
          },
          {
            'title': 'Finalize budget allocation for teaser campaign',
            'owner': 'Priya',
          },
          {
            'title': 'Schedule follow-up design review for Vault UI',
            'owner': 'Jordan',
          },
        ],
        'confidence_percent': 96,
        'saved_to_vault': true,
        'high_fidelity_confirmed': true,
        'citations': [
          {'title': 'q3_planning_sync_raw.m4a'},
        ],
      },
    ],
    'tasks': const [],
    'memory_records': const [],
    'recurring_reminder_rules': const [],
    'approval_items': [
      if (!resolvedApprovalIds.contains('approval-action-act091'))
        const {
          'id': 'approval-action-act091',
          'kind': 'action_item_candidate',
          'title': 'Draft phased rollout schedule for Vault feature',
          'reason':
              'Create an action item from the Q3 Planning Sync transcript.',
          'source_intent_id': 'ACT-091',
          'record': {
            'kind': 'action_item_candidate',
            'candidate_id': 'ACT-091',
            'title': 'Draft phased rollout schedule for Vault feature',
            'description':
                'Capture the rollout schedule commitment before Q3 planning closes.',
            'due_label': 'Aug 5, 2026',
            'source_timestamp': '12:05',
            'risk': 'Low',
            'source_id': 'MTG-Q3-2026-001',
          },
        },
      if (!resolvedApprovalIds.contains('approval-action-act092'))
        const {
          'id': 'approval-action-act092',
          'kind': 'action_item_candidate',
          'title': 'Finalize budget allocation for teaser campaign',
          'reason':
              'Create an action item from the Q3 Planning Sync transcript.',
          'source_intent_id': 'ACT-092',
          'record': {
            'kind': 'action_item_candidate',
            'candidate_id': 'ACT-092',
            'title': 'Finalize budget allocation for teaser campaign',
            'source_timestamp': '28:30',
            'risk': 'Low',
            'source_id': 'MTG-Q3-2026-001',
          },
        },
      if (!resolvedApprovalIds.contains('approval-action-act093'))
        const {
          'id': 'approval-action-act093',
          'kind': 'action_item_candidate',
          'title': 'Schedule follow-up design review for Vault UI',
          'reason':
              'Create an action item from the Q3 Planning Sync transcript.',
          'source_intent_id': 'ACT-093',
          'record': {
            'kind': 'action_item_candidate',
            'candidate_id': 'ACT-093',
            'title': 'Schedule follow-up design review for Vault UI',
            'source_timestamp': '41:15',
            'risk': 'Low',
            'source_id': 'MTG-Q3-2026-001',
          },
        },
    ],
    'recent_entity_refs': const [
      {
        'entity_id': 'att-q3-sync',
        'kind': 'attachment',
        'label': 'q3_planning_sync_raw.m4a',
      },
    ],
    'latest_context_snapshot': const {
      'id': 'CTX-MEETING-0803',
      'generated_at_ms': 1785758460000,
      'packet': {
        'working_set': {
          'records': [],
        },
      },
    },
    'audit_refs': const [
      {'id': 'MTG-Q3-2026-001'},
    ],
  });
}

final class _MeetingAudioRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  final Set<String> resolvedApprovalIds = <String>{};

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _seventhScreenState(resolvedApprovalIds: resolvedApprovalIds);
  }
}

final class _MeetingAudioApprovalRecordingSender
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeApprovalSender,
        ChatRuntimeAttachmentContentFetcher {
  _MeetingAudioApprovalRecordingSender(this.repository);

  final _MeetingAudioRuntimeAgentStateRepository repository;
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
    repository.resolvedApprovalIds.add(approvalId);
    return null;
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('action candidates are not editable in this fixture');
  }

  @override
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  }) async {
    return attachmentId == 'att-q3-sync'
        ? Uint8List.fromList(const [0, 1, 2, 3])
        : null;
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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
