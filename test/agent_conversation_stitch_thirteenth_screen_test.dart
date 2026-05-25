import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/core/quick_capture/quick_capture_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'thirteenth canonical Stitch screen renders the 2560 desktop workbench',
    (tester) async {
      final harness = await _pumpWorkbench(
        tester,
        size: const Size(2560, 2048),
      );

      expect(find.byKey(const ValueKey('app_shell_desktop_workbench')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('desktop_workbench_chat_column')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('desktop_workbench_side_panels')),
          findsOneWidget);

      for (final label in const [
        'Briefing',
        'Chat',
        'Vault',
        'Tasks',
        'Memory',
        'Approvals',
        'Connectors',
        'Settings',
      ]) {
        expect(find.text(label), findsWidgets);
      }

      expect(find.text('介绍一下新的手机产品参数。'), findsOneWidget);
      expect(find.textContaining('previous Apple launch research context'),
          findsOneWidget);
      expect(find.text('Citations from web-research'), findsOneWidget);
      expect(find.text('Phone product from cited result'), findsOneWidget);
      expect(find.text('Display / chip / camera / battery fields available'),
          findsOneWidget);
      expect(find.text('Sources [1]'), findsOneWidget);

      expect(find.text('Runtime Context'), findsOneWidget);
      expect(find.text('previous Apple launch research'), findsOneWidget);
      expect(
        find.text('context snapshot includes previous Apple launch query'),
        findsOneWidget,
      );
      expect(find.text('User prefers Chinese (Pinned)'), findsOneWidget);

      expect(find.text('Pending Approvals'), findsOneWidget);
      expect(find.text('Task Mutation Approval'), findsOneWidget);
      expect(find.text("Change requested for 'Expense Management'"),
          findsOneWidget);
      expect(find.text('整理报销材料'), findsOneWidget);
      expect(find.text('提交报销'), findsOneWidget);

      expect(find.text('Tool Trace'), findsOneWidget);
      expect(find.text('web-research: executed'), findsOneWidget);
      expect(find.text('CITATIONS: PRESENT'), findsOneWidget);
      expect(find.text('skill_result_response'), findsOneWidget);
      expect(find.text('web-research required'), findsOneWidget);
      expect(find.textContaining('Latency: 1.24s'), findsOneWidget);

      final topNav = tester.getRect(
        find.byKey(const ValueKey('app_shell_desktop_top_nav')),
      );
      final sidebar = tester.getRect(
        find.byKey(const ValueKey('app_shell_sidebar')),
      );
      final workspace = tester.getRect(
        find.byKey(const ValueKey('agent_conversation_workspace')),
      );
      final composer = tester.getRect(
        find.byKey(const ValueKey('desktop_workbench_composer_box')),
      );

      expect(topNav, const Rect.fromLTWH(0, 0, 2560, 64));
      expect(sidebar.width, 256);
      expect(sidebar.height, 1984);
      expect(workspace.left, 256);
      expect(workspace.top, 64);
      expect(workspace.width, 2304);
      expect(composer.width, 896);
      expect(find.byKey(const ValueKey('app_shell_desktop_quick_capture')),
          findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('app_shell_desktop_quick_capture')),
      );
      await tester.pump();
      expect(harness.quickCapture.visible, isTrue);
    },
  );

  testWidgets('desktop workbench actions are wired or honestly degraded',
      (tester) async {
    final harness = await _pumpWorkbench(
      tester,
      size: const Size(1440, 1024),
    );

    expect(find.byKey(const ValueKey('desktop_workbench_chat_column')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('app_shell_desktop_vault_search')),
    );
    await tester.pump();
    expect(find.textContaining('tool_unavailable'), findsOneWidget);

    await tester.tap(find.text('Connectors'));
    await tester.pump();
    expect(find.textContaining('needs_configuration'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(harness.sender.decisions, [
      ('uid_1', 'approval-task-title', 'approve'),
    ]);
  });

  testWidgets('desktop tool trace fails closed when citations are absent',
      (tester) async {
    await _pumpWorkbench(
      tester,
      size: const Size(1440, 1024),
      state: _desktopWorkbenchState(includeCitations: false),
    );

    expect(find.text('web-research: executed'), findsOneWidget);
    expect(find.text('CITATIONS: MISSING'), findsOneWidget);
    expect(find.text('CITATIONS: PRESENT'), findsNothing);
  });

  testWidgets('non-workbench breakpoint keeps the responsive chat shell',
      (tester) async {
    await _pumpWorkbench(
      tester,
      size: const Size(1199, 1057),
    );

    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_workbench_chat_column')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_operating_message_list')),
        findsOneWidget);
  });
}

Future<_WorkbenchHarness> _pumpWorkbench(
  WidgetTester tester, {
  required Size size,
  RuntimeAgentState? state,
}) async {
  final repository = _FakeRuntimeAgentStateRepository(
    state ?? _desktopWorkbenchState(),
  );
  final sender = _ApprovalRecordingSender();
  final quickCapture = QuickCaptureController();

  await tester.binding.setSurfaceSize(size);
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
              child: QuickCaptureScope(
                controller: quickCapture,
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
    ),
  );
  await tester.pumpAndSettle();

  return _WorkbenchHarness(
    sender: sender,
    quickCapture: quickCapture,
  );
}

RuntimeAgentState _desktopWorkbenchState({bool includeCitations = true}) {
  final citationsJson = includeCitations
      ? '{"direct_sources":[{"id":"src-1","href":"https://example.com/apple-launch","source_type":"web_research","label":"Source [1]","title":"Phone product from cited result","snippet":"Display / chip / camera / battery fields available"},{"id":"src-2","href":"https://example.com/specs","source_type":"web_research","label":"Source [2]","title":"Availability details","snippet":"Requires source check before acting"}]}'
      : null;
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      const {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我创建一个任务：完成周报。记住：任务回复请使用中文。',
        'created_at_ms': 1780292520000,
      },
      const {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '已创建任务。',
        'created_at_ms': 1780292521000,
      },
      const {
        'turn_id': 'turn-user-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '介绍一下新的手机产品参数。',
        'created_at_ms': 1780292700000,
      },
      {
        'turn_id': 'turn-assistant-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content':
            'Continuing from the previous Apple launch research context, I found the phone products referenced in the cited results and summarized their parameter groups below. Open each citation before using the details as current facts.',
        if (citationsJson != null) 'citations_json': citationsJson,
        'tool_trace': const {
          'skill': 'web-research',
          'status': 'executed',
          'postprocess': 'skill_result_response',
          'current_facts': 'web-research required',
          'latency_ms': 1240,
        },
        'created_at_ms': 1780292701000,
      },
    ],
    'working_set_records': const [],
    'tasks': const [
      {
        'id': 'task-weekly',
        'kind': 'task',
        'title': '完成周报',
        'status': 'open',
        'source_message_id': 'turn-user-1',
        'audit_id': 'TXN-2026-06-01',
        'created_at_ms': 1780292521000,
      }
    ],
    'memory_records': const [
      {
        'id': 'mem-zh',
        'kind': 'memory',
        'title': 'User prefers Chinese',
        'status': 'active',
      }
    ],
    'recurring_reminder_rules': const [],
    'approval_items': const [
      {
        'id': 'approval-task-title',
        'kind': 'task_mutation_confirmation',
        'title': 'Task Mutation Approval',
        'record': {
          'task_title': 'Expense Management',
          'before': '整理报销材料',
          'after': '提交报销',
        },
      }
    ],
    'recent_entity_refs': const [
      {
        'entity_type': 'task',
        'title': '完成周报',
      }
    ],
    'latest_context_snapshot': const {
      'id': 'ctx-1',
      'generated_at_ms': 1780292701000,
      'packet': {
        'recent_turns': 'previous Apple launch research',
        'context_status':
            'context snapshot includes previous Apple launch query',
      },
    },
    'audit_refs': const [
      {
        'id': 'TXN-2026-06-01',
      }
    ],
  });
}

final class _WorkbenchHarness {
  const _WorkbenchHarness({
    required this.sender,
    required this.quickCapture,
  });

  final _ApprovalRecordingSender sender;
  final QuickCaptureController quickCapture;
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
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeApprovalSender,
        ChatRuntimeEntityFocusSender {
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
    return null;
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    throw StateError('patch should not be used');
  }

  @override
  Future<void> recordEntityFocus({
    required String vaultId,
    required String conversationId,
    required String entityType,
    required String entityId,
    required String title,
  }) async {}
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
