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
    'fifth canonical Stitch screen renders calendar approval from runtime state',
    (tester) async {
      final repository = _CalendarRuntimeAgentStateRepository();
      final sender = _CalendarApprovalRecordingSender(repository);

      await _pumpFifthScreen(
        tester: tester,
        size: const Size(780, 2172),
        repository: repository,
        sender: sender,
      );

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(
        find.text('Extract my travel dates from the attached email.'),
        findsOneWidget,
      );
      expect(find.text('Fwd: Itinerary for NYC Trip - June'), findsOneWidget);
      expect(find.text('14 KB • PDF'), findsOneWidget);
      expect(find.text('email-analysis'), findsOneWidget);
      expect(find.text('memory-capture'), findsOneWidget);
      expect(find.text('calendar-skill'), findsOneWidget);
      expect(
        find.text(
          "I've analyzed the email. I found upcoming travel to New York City "
          'and a related calendar action. Please review the extracted '
          'information below.',
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey('agent_operating_memory_candidate_mem_2026_06_10'),
        ),
        findsOneWidget,
      );
      expect(find.text('Memory Candidate'), findsOneWidget);
      expect(find.text('Travel: NYC June 10-15, 2026'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey(
            'calendar_event_approval_card_approval-calendar-nyc-design',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Calendar Event Approval'), findsOneWidget);
      expect(find.text('calendar_tool'), findsOneWidget);
      expect(find.text('Proposed Event'.toUpperCase()), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('calendar_event_title_cal_2026_06_12'),
        ),
        findsOneWidget,
      );
      expect(find.text('Meeting with NYC Design Team'), findsOneWidget);
      expect(
        find.text('June 12, 2026, 10:00 AM - 11:00 AM'),
        findsOneWidget,
      );
      expect(find.text('Sarah J., Mike T., Elena R.'), findsOneWidget);
      expect(
        find.text('Extracted from Fwd: Itinerary for NYC Trip - June'),
        findsOneWidget,
      );
      expect(
        find.text(
            'Event will not be created until approved by user account owner.'),
        findsOneWidget,
      );
      expect(find.text('Audit Trail'.toUpperCase()), findsOneWidget);
      expect(find.text('cal_2026_06_12'), findsWidgets);
      expect(find.text('Sync Priority'.toUpperCase()), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Edit unavailable'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey('calendar_event_approve_approval-calendar-nyc-design'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('calendar_event_approve_approval-calendar-nyc-design'),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-calendar-nyc-design', 'approve'),
      ]);
      expect(
        find.byKey(
          const ValueKey(
            'calendar_event_approval_card_approval-calendar-nyc-design',
          ),
        ),
        findsNothing,
      );
      expect(find.text('Travel: NYC June 10-15, 2026'), findsOneWidget);
    },
  );

  testWidgets(
    'calendar approval keeps required evidence across widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 1800),
        Size(780, 2172),
        Size(1180, 1600),
      ];
      for (final size in sizes) {
        final repository = _CalendarRuntimeAgentStateRepository();
        await _pumpFifthScreen(
          tester: tester,
          size: size,
          repository: repository,
          sender: _CalendarApprovalRecordingSender(repository),
        );

        final card = find.byKey(
          const ValueKey(
            'calendar_event_approval_card_approval-calendar-nyc-design',
          ),
        );
        expect(card, findsOneWidget, reason: 'screen width ${size.width}');
        expect(find.text('Memory Candidate'), findsOneWidget);
        expect(find.text('Calendar Event Approval'), findsOneWidget);
        expect(find.text('Meeting with NYC Design Team'), findsOneWidget);
        expect(find.text('June 12, 2026, 10:00 AM - 11:00 AM'), findsOneWidget);
        expect(find.text('Sarah J., Mike T., Elena R.'), findsOneWidget);
        expect(find.text('calendar_tool'), findsOneWidget);
        expect(find.text('cal_2026_06_12'), findsWidgets);
        expect(find.text('Standard'), findsOneWidget);
        expect(find.text('Edit unavailable'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(
            const ValueKey(
              'calendar_event_approve_approval-calendar-nyc-design',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                const ValueKey(
                  'calendar_event_approve_approval-calendar-nyc-design',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(
                const ValueKey(
                  'calendar_event_reject_approval-calendar-nyc-design',
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

Future<void> _pumpFifthScreen({
  required WidgetTester tester,
  required Size size,
  required _CalendarRuntimeAgentStateRepository repository,
  required _CalendarApprovalRecordingSender sender,
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

RuntimeAgentState _fifthScreenState({required bool calendarApproved}) {
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': const [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': 'Extract my travel dates from the attached email.',
        'created_at_ms': 1781034000000,
        'attachments': [
          {
            'id': 'att-nyc-itinerary',
            'filename': 'Fwd: Itinerary for NYC Trip - June',
            'mime_type': 'application/pdf',
            'media_type': 'document',
            'size_label': '14 KB • PDF',
          },
        ],
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            "I've analyzed the email. I found upcoming travel to New York City "
                'and a related calendar action. Please review the extracted '
                'information below.',
        'created_at_ms': 1781034060000,
      },
    ],
    'working_set_records': const [],
    'tasks': const [],
    'memory_records': const [],
    'recurring_reminder_rules': const [],
    'approval_items': [
      const {
        'id': 'mem_2026_06_10',
        'kind': 'memory_confirmation',
        'title': 'Travel: NYC June 10-15, 2026',
        'record': {
          'text': 'Travel: NYC June 10-15, 2026',
          'source': 'Email',
          'conflict_risk': 'Low',
          'audit_id': 'mem_2026_06_10',
        },
      },
      if (!calendarApproved)
        const {
          'id': 'approval-calendar-nyc-design',
          'kind': 'calendar_event_confirmation',
          'calendar_event_id': 'cal_2026_06_12',
          'title': 'Meeting with NYC Design Team',
          'reason': 'Extracted from Fwd: Itinerary for NYC Trip - June',
          'record': {
            'id': 'cal_2026_06_12',
            'title': 'Meeting with NYC Design Team',
            'time_label': 'June 12, 2026, 10:00 AM - 11:00 AM',
            'participants': ['Sarah J.', 'Mike T.', 'Elena R.'],
            'source_message':
                'Extracted from Fwd: Itinerary for NYC Trip - June',
            'tool_label': 'calendar_tool',
            'audit_id': 'cal_2026_06_12',
            'context_snapshot_id': 'CTX-CAL-0612',
            'sync_priority': 'Standard',
            'approval_status': 'pending',
            'notice':
                'Event will not be created until approved by user account owner.',
          },
        },
    ],
    'recent_entity_refs': const [
      {
        'entity_id': 'att-nyc-itinerary',
        'kind': 'attachment',
        'label': 'Fwd: Itinerary for NYC Trip - June',
      },
    ],
    'latest_context_snapshot': const {
      'id': 'CTX-CAL-0612',
      'generated_at_ms': 1781034060000,
      'packet': {
        'attachment': 'att-nyc-itinerary',
        'runtime_tool': 'calendar_tool',
      },
    },
    'audit_refs': const [
      {'id': 'cal_2026_06_12'},
    ],
  });
}

final class _CalendarRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  bool calendarApproved = false;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _fifthScreenState(calendarApproved: calendarApproved);
  }
}

final class _CalendarApprovalRecordingSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  _CalendarApprovalRecordingSender(this.repository);

  final _CalendarRuntimeAgentStateRepository repository;
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
    if (approvalId == 'approval-calendar-nyc-design' && decision == 'approve') {
      repository.calendarApproved = true;
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
    throw StateError('calendar edit should be unavailable');
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
