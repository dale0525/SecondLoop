import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RuntimeConnectionStore.resetCacheForTests();
  });

  testWidgets('798px shell uses final Stitch mobile navigation order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(798, 1057));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            chatTabBuilder: (_, __) => const SizedBox(key: ValueKey('chat')),
            notesTabBuilder: (_, __) => const SizedBox(key: ValueKey('vault')),
            memoryTabBuilder: (_, __) => const SizedBox(key: ValueKey('tasks')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('briefing')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('settings')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app_shell_bottom_nav')), findsOneWidget);
    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsNothing);

    final labels = ['Briefing', 'Chat', 'Vault', 'Tasks', 'Settings'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(_leftOf(tester, 'Briefing'), lessThan(_leftOf(tester, 'Chat')));
    expect(_leftOf(tester, 'Chat'), lessThan(_leftOf(tester, 'Vault')));
    expect(_leftOf(tester, 'Vault'), lessThan(_leftOf(tester, 'Tasks')));
    expect(_leftOf(tester, 'Tasks'), lessThan(_leftOf(tester, 'Settings')));
    expect(find.byKey(const ValueKey('chat')), findsOneWidget);
  });

  testWidgets('first canonical Stitch chat screen renders runtime-backed cards',
      (tester) async {
    final repository = _FakeRuntimeAgentStateRepository(_firstScreenState());
    final sender = _ApprovalRecordingSender();

    await tester.binding.setSurfaceSize(const Size(798, 1057));
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
                child: AgentConversationPage(
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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SecondLoop Agent'), findsOneWidget);
    expect(find.text('Managed Pro'), findsOneWidget);
    expect(find.text('router'), findsOneWidget);
    expect(find.text('task-management'), findsOneWidget);
    expect(find.text('memory-capture'), findsOneWidget);
    expect(find.text('vault write'), findsOneWidget);
    expect(find.text('Task Created'), findsOneWidget);
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Mutation ID'), findsOneWidget);
    expect(find.text('mut_88291_sl'), findsOneWidget);
    expect(find.text('Memory Candidate'), findsOneWidget);
    expect(find.text('Pending Approval'), findsOneWidget);
    expect(find.text('Risk Score:'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Entity Ref:'), findsOneWidget);
    expect(find.text('task:"完成周报"'), findsOneWidget);
    expect(find.text('Active Memory:'), findsOneWidget);
    expect(find.text('none yet'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('agent_operating_open_task_task-weekly')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('agent_task_detail_sheet')), findsOneWidget);
    Navigator.of(tester
            .element(find.byKey(const ValueKey('agent_task_detail_sheet'))))
        .pop();
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const ValueKey('agent_operating_memory_approve_mem-pref')));
    await tester.pumpAndSettle();
    expect(sender.decisions, [('uid_1', 'mem-pref', 'approve')]);
  });

  testWidgets('chat top bar labels stored self-managed runtime',
      (tester) async {
    await RuntimeConnectionStore().saveConnection(_selfManagedConnection);
    final repository = _FakeRuntimeAgentStateRepository(_firstScreenState());

    await tester.binding.setSurfaceSize(const Size(798, 1057));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: AgentConversationPage(
                conversation: const Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
                isTabActive: true,
                runtimeConversationSender: _ApprovalRecordingSender(),
                runtimeAgentStateRepository: repository,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Self-managed'), findsOneWidget);
    expect(find.text('Managed Pro'), findsNothing);
  });

  testWidgets('bottom-nav widths keep the Stitch chat shell', (tester) async {
    final repository = _FakeRuntimeAgentStateRepository(_firstScreenState());
    final sender = _ApprovalRecordingSender();

    await tester.binding.setSurfaceSize(const Size(900, 1057));
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

    expect(find.byKey(const ValueKey('app_shell_bottom_nav')), findsOneWidget);
    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsNothing);
    expect(find.text('SecondLoop Agent'), findsOneWidget);
    expect(find.text('Managed Pro'), findsOneWidget);
    expect(find.text('Task Created'), findsOneWidget);
    expect(find.text('Memory Candidate'), findsOneWidget);
  });

  testWidgets('intermediate desktop widths render the Stitch agent workbench',
      (tester) async {
    final repository = _FakeRuntimeAgentStateRepository(_firstScreenState());

    await tester.binding.setSurfaceSize(const Size(1199, 1057));
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
                    runtimeConversationSender: _ApprovalRecordingSender(),
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

    expect(find.byKey(const ValueKey('app_shell_bottom_nav')), findsNothing);
    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_workbench_chat_column')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('agent_operating_message_list')),
        findsNothing);
    expect(find.text('SecondLoop Agent'), findsNothing);
    expect(find.textContaining('长期记忆候选'), findsOneWidget);
    expect(find.text('Pending Approvals'), findsOneWidget);
  });

  testWidgets('desktop widths render the Stitch agent workbench',
      (tester) async {
    final repository =
        _FakeRuntimeAgentStateRepository(_desktopWorkbenchState());
    final sender = _ApprovalRecordingSender();

    await tester.binding.setSurfaceSize(const Size(1440, 1024));
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

    expect(find.byKey(const ValueKey('app_shell_desktop_workbench')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app_shell_desktop_top_nav')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsOneWidget);
    expect(find.text('Runtime Synced'), findsOneWidget);
    expect(find.text('Search operational vault...'), findsOneWidget);
    for (final label in [
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
    expect(find.text('Runtime Context'), findsOneWidget);
    expect(find.text('Pending Approvals'), findsOneWidget);
    expect(find.text('Tool Trace'), findsOneWidget);
    expect(find.text('web-research: executed'), findsOneWidget);
    expect(find.text('CITATIONS: PRESENT'), findsOneWidget);
    expect(find.text('web-research required'), findsOneWidget);
    expect(find.text('Task Mutation Approval'), findsOneWidget);
  });

  testWidgets('desktop workbench matches the Stitch 2560 layout frame',
      (tester) async {
    final repository =
        _FakeRuntimeAgentStateRepository(_desktopWorkbenchState());

    await tester.binding.setSurfaceSize(const Size(2560, 2048));
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
                    runtimeConversationSender: _ApprovalRecordingSender(),
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

    final topNav = tester.getRect(
      find.byKey(const ValueKey('app_shell_desktop_top_nav')),
    );
    final sidebar = tester.getRect(
      find.byKey(const ValueKey('app_shell_sidebar')),
    );
    final workspace = tester.getRect(
      find.byKey(const ValueKey('agent_conversation_workspace')),
    );
    final chatColumn = tester.getRect(
      find.byKey(const ValueKey('desktop_workbench_chat_column')),
    );
    final sidePanels = tester.getRect(
      find.byKey(const ValueKey('desktop_workbench_side_panels')),
    );
    final composer = tester.getRect(
      find.byKey(const ValueKey('desktop_workbench_composer_box')),
    );

    expect(topNav, const Rect.fromLTWH(0, 0, 2560, 64));
    expect(sidebar.left, 0);
    expect(sidebar.top, 64);
    expect(sidebar.width, 256);
    expect(sidebar.height, 1984);
    expect(workspace.left, 256);
    expect(workspace.top, 64);
    expect(workspace.width, 2304);
    expect(workspace.height, 1984);
    expect(chatColumn.width, closeTo(1344, 1));
    expect(sidePanels.width, closeTo(959, 1));
    expect(composer.width, 896);
    expect(find.byKey(const ValueKey('app_shell_desktop_quick_capture')),
        findsNothing);
  });
}

RuntimeAgentState _firstScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我创建一个任务：完成周报。记住：任务回复请使用中文。',
        'created_at_ms': 1700000000000,
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '我已创建普通任务，并准备了一条长期记忆候选。',
        'created_at_ms': 1700000000100,
      },
    ],
    'working_set_records': [],
    'tasks': [
      {
        'id': 'task-weekly',
        'kind': 'task',
        'title': '完成周报',
        'status': 'open',
        'source_message_id': 'turn-user-1',
        'mutation_id': 'mut_88291_sl',
        'audit_id': 'aud_ctx_440',
        'created_at_ms': 1700000000100,
      }
    ],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [
      {
        'id': 'mem-pref',
        'kind': 'memory_confirmation',
        'title': '任务相关回复默认使用中文',
        'reason':
            'User asked SecondLoop to remember a reply-language preference.',
        'record': {
          'text': '任务相关回复默认使用中文',
          'conflict_risk': 'Low',
          'audit_id': 'mem_ctx_012',
        },
      }
    ],
    'recent_entity_refs': [
      {
        'entity_type': 'task',
        'title': '完成周报',
      }
    ],
    'latest_context_snapshot': null,
    'audit_refs': [
      {
        'id': 'aud_ctx_440',
      }
    ],
  });
}

RuntimeAgentState _desktopWorkbenchState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我创建一个任务：完成周报。记住：任务回复请使用中文。',
        'created_at_ms': 1780292520000,
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '已创建任务。',
        'created_at_ms': 1780292521000,
      },
      {
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
        'citations_json':
            '{"direct_sources":[{"id":"src-1","href":"https://example.com/apple-launch","source_type":"web_research","label":"Source [1]","title":"Apple launch reference","snippet":"Phone product from cited result"},{"id":"src-2","href":"https://example.com/specs","source_type":"web_research","label":"Source [2]","title":"Availability details","snippet":"Requires source check before acting"}]}',
        'tool_trace': {
          'skill': 'web-research',
          'status': 'executed',
          'postprocess': 'skill_result_response',
          'current_facts': 'web-research required',
          'latency_ms': 1240,
        },
        'created_at_ms': 1780292701000,
      },
    ],
    'working_set_records': [],
    'tasks': [
      {
        'id': 'task-weekly',
        'kind': 'task',
        'title': '完成周报',
        'status': 'open',
        'source_message_id': 'turn-user-1',
        'mutation_id': 'mut_88291_sl',
        'audit_id': 'TXN-2026-06-01',
        'created_at_ms': 1780292521000,
      }
    ],
    'memory_records': [
      {
        'id': 'mem-zh',
        'kind': 'memory',
        'title': 'User prefers Chinese',
        'status': 'active',
      }
    ],
    'recurring_reminder_rules': [],
    'approval_items': [
      {
        'id': 'task-mut-1',
        'kind': 'task_mutation',
        'title': 'Task Mutation Approval',
        'record': {
          'task_title': 'Expense Management',
          'before': '整理报销材料',
          'after': '提交报销',
        },
      }
    ],
    'recent_entity_refs': [
      {
        'entity_type': 'task',
        'title': '完成周报',
      }
    ],
    'latest_context_snapshot': {
      'id': 'ctx-1',
      'generated_at_ms': 1780292701000,
      'packet': {
        'recent_turns': 'previous Apple launch research',
        'context_status':
            'context snapshot includes previous Apple launch query',
      },
    },
    'audit_refs': [
      {
        'id': 'TXN-2026-06-01',
      }
    ],
  });
}

double _leftOf(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text)).dx;
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _FakeRuntimeAgentStateRepository(this.state);

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

const _selfManagedConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    vaultId: 'acct-1',
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: CloudRuntimeRequiredCapabilities.all,
  ),
);

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
