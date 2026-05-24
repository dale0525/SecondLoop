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
    'fourth canonical Stitch screen renders task mutation approval',
    (tester) async {
      final repository = _MutableRuntimeAgentStateRepository();
      final sender = _TaskMutationRecordingSender(repository);

      await tester.binding.setSurfaceSize(const Size(780, 2938));
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

      expect(find.text('SecondLoop Agent'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('帮我创建一个任务：整理报销材料。'), findsOneWidget);
      expect(find.text('已创建任务：整理报销材料。'), findsOneWidget);
      expect(find.text('把上一个待办事项标题改为提交报销。'), findsOneWidget);
      expect(find.text('待确认：把任务标题改为“提交报销”。'), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey('task_mutation_approval_card_approval-task-title'),
        ),
        findsOneWidget,
      );
      expect(find.text('Task Title Change Approval'), findsOneWidget);
      expect(find.text('Low Risk'), findsOneWidget);
      expect(find.text('System Context'.toUpperCase()), findsOneWidget);
      expect(
        find.text(
          'Task "整理报销材料" was successfully initialized in thread #4429.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Current State (Awaiting Approval)'.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('task_mutation_current_title_T-88291')),
        findsOneWidget,
      );
      expect(find.text('Due: Today'), findsOneWidget);
      expect(find.text('Target Entity'.toUpperCase()), findsOneWidget);
      expect(find.text('T-88291'), findsWidgets);
      expect(find.text('Resolver Detail'.toUpperCase()), findsOneWidget);
      expect(
        find.text('recent_ref resolved to most recent task'),
        findsOneWidget,
      );
      expect(find.text('Proposed Change'.toUpperCase()), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('task_mutation_proposed_title_approval-task-title'),
        ),
        findsOneWidget,
      );
      expect(find.text('Source'), findsWidgets);
      expect(find.text('Chat Message'), findsOneWidget);
      expect(find.text('Audit ID'), findsWidgets);
      expect(find.text('TXN-2026-05-12'), findsWidgets);
      expect(find.text('Context Snapshot'), findsWidgets);
      expect(find.text('CTX-9921'), findsWidgets);
      expect(find.text('Runtime Tool'), findsWidgets);
      expect(find.text('task-management'), findsWidgets);
      expect(
        find.text('Mutation is not applied until approved.'),
        findsOneWidget,
      );
      expect(find.text('Last Approved Change'), findsOneWidget);
      expect(
          find.text('Task Priority: High -> Normal (2h ago)'), findsOneWidget);
      expect(find.text('Automation Confidence'), findsOneWidget);
      expect(find.text('98.4% Match to Entity T-88291'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('task_mutation_edit_approval-task-title')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey('task_mutation_title_field_approval-task-title'),
        ),
        '提交报销并归档材料',
      );
      await tester.tap(
        find.byKey(
          const ValueKey('task_mutation_save_title_approval-task-title'),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.approvalPatches, [
        'approval-task-title:1:提交报销并归档材料',
      ]);
      expect(find.text('提交报销并归档材料'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('task_mutation_approve_approval-task-title')),
      );
      await tester.pumpAndSettle();

      expect(sender.decisions, [
        ('uid_1', 'approval-task-title', 'approve'),
      ]);
      expect(
        find.byKey(
          const ValueKey('task_mutation_approval_card_approval-task-title'),
        ),
        findsNothing,
      );
      expect(find.text('提交报销并归档材料'), findsOneWidget);
    },
  );

  testWidgets(
    'task mutation approval keeps required evidence across widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const sizes = [
        Size(390, 2400),
        Size(780, 2938),
        Size(1180, 1600),
      ];
      for (final size in sizes) {
        final repository = _MutableRuntimeAgentStateRepository();
        await _pumpFourthScreen(
          tester: tester,
          size: size,
          repository: repository,
          sender: _TaskMutationRecordingSender(repository),
        );

        final card = find.byKey(
          const ValueKey('task_mutation_approval_card_approval-task-title'),
        );
        expect(card, findsOneWidget, reason: 'screen width ${size.width}');
        expect(find.text('Task Title Change Approval'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('task_mutation_current_title_T-88291')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('task_mutation_proposed_title_approval-task-title'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('recent_ref resolved to most recent task'),
          findsOneWidget,
        );
        expect(find.text('TXN-2026-05-12'), findsWidgets);
        expect(find.text('CTX-9921'), findsWidgets);
        expect(find.text('task-management'), findsWidgets);
        expect(
          find.text('Mutation is not applied until approved.'),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(
            const ValueKey('task_mutation_approve_approval-task-title'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                const ValueKey('task_mutation_approve_approval-task-title'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(const ValueKey('task_mutation_edit_approval-task-title'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(
                const ValueKey('task_mutation_reject_approval-task-title'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'screen width $size');
      }
    },
  );
}

Future<void> _pumpFourthScreen({
  required WidgetTester tester,
  required Size size,
  required _MutableRuntimeAgentStateRepository repository,
  required _TaskMutationRecordingSender sender,
}) async {
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

RuntimeAgentState _fourthScreenState({
  required bool approved,
  required String proposedTitle,
}) {
  final activeTitle = approved ? proposedTitle : '整理报销材料';
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      const {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '帮我创建一个任务：整理报销材料。',
        'created_at_ms': 1778565600000,
      },
      const {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '已创建任务：整理报销材料。',
        'created_at_ms': 1778565660000,
      },
      const {
        'turn_id': 'turn-user-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '把上一个待办事项标题改为提交报销。',
        'created_at_ms': 1778565720000,
      },
      {
        'turn_id': 'turn-assistant-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': approved ? '已批准并更新任务标题。' : '待确认：把任务标题改为“提交报销”。',
        'created_at_ms': 1778565780000,
      },
    ],
    'working_set_records': const [],
    'tasks': [
      {
        'id': 'T-88291',
        'kind': 'task',
        'title': activeTitle,
        'status': 'todo',
        'due_label': 'Due: Today',
        'source_message_id': 'turn-assistant-1',
        'created_at_ms': 1778565660000,
        'updated_at_ms': approved ? 1778565900000 : 1778565660000,
      },
      const {
        'id': 'T-55102',
        'kind': 'task',
        'title': 'Weekly Sync Meeting',
        'status': 'todo',
        'due_label': 'Due: Tomorrow',
        'created_at_ms': 1778560000000,
        'updated_at_ms': 1778560000000,
      },
    ],
    'memory_records': const [],
    'recurring_reminder_rules': const [],
    'approval_items': approved
        ? const []
        : [
            {
              'id': 'approval-task-title',
              'task_id': 'T-88291',
              'title': proposedTitle,
              'kind': 'task_mutation_confirmation',
              'editable_fields': const ['title'],
              'version': 1,
              'record': {
                'id': 'T-88291',
                'current_title': '整理报销材料',
                'proposed_title': proposedTitle,
                'resolver_detail': 'recent_ref resolved to most recent task',
                'source': 'Chat Message',
                'audit_id': 'TXN-2026-05-12',
                'context_snapshot_id': 'CTX-9921',
                'runtime_tool': 'task-management',
                'risk_label': 'Low Risk',
                'current_state_label': 'Due: Today',
                'thread_label': 'thread #4429',
                'notice': 'Mutation is not applied until approved.',
                'last_approved_change':
                    'Task Priority: High -> Normal (2h ago)',
                'confidence_label': '98.4% Match to Entity T-88291',
              },
            },
          ],
    'recent_entity_refs': const [
      {
        'entity_id': 'T-88291',
        'kind': 'task',
        'resolver_detail': 'recent_ref resolved to most recent task',
      },
    ],
    'latest_context_snapshot': const {
      'id': 'CTX-9921',
      'generated_at_ms': 1778565780000,
      'packet': {
        'recent_entity_refs': 'T-88291',
        'runtime_tool': 'task-management',
      },
    },
    'audit_refs': const [
      {'id': 'TXN-2026-05-12'},
    ],
  });
}

final class _MutableRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  bool approved = false;
  String proposedTitle = '提交报销';

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return _fourthScreenState(
      approved: approved,
      proposedTitle: proposedTitle,
    );
  }
}

final class _TaskMutationRecordingSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  _TaskMutationRecordingSender(this.repository);

  final _MutableRuntimeAgentStateRepository repository;
  final List<(String, String, String)> decisions = <(String, String, String)>[];
  final List<String> approvalPatches = <String>[];

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
    if (decision == 'approve') {
      repository.approved = true;
    }
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
    repository.proposedTitle = title;
    approvalPatches.add('$approvalId:$baseVersion:$title');
    return SecretaryRuntimeApprovalItem(
      id: approvalId,
      taskId: 'T-88291',
      title: title,
      kind: 'task_mutation_confirmation',
      editableFields: const ['title'],
      version: baseVersion + 1,
      record: <String, Object?>{
        'id': 'T-88291',
        'current_title': '整理报销材料',
        'proposed_title': title,
        'resolver_detail': 'recent_ref resolved to most recent task',
        'source': 'Chat Message',
        'audit_id': 'TXN-2026-05-12',
        'context_snapshot_id': 'CTX-9921',
        'runtime_tool': 'task-management',
        'risk_label': 'Low Risk',
        'current_state_label': 'Due: Today',
        'thread_label': 'thread #4429',
        'notice': 'Mutation is not applied until approved.',
        'last_approved_change': 'Task Priority: High -> Normal (2h ago)',
        'confidence_label': '98.4% Match to Entity T-88291',
      },
    );
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
