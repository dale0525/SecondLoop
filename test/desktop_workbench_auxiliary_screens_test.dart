import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/features/agent_ui/desktop_approvals_workbench_page.dart';
import 'package:secondloop/features/agent_ui/desktop_connectors_workbench_page.dart';
import 'package:secondloop/features/agent_ui/desktop_memory_workbench_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'desktop sidebar restores Memory Approvals and Connectors screens',
      (tester) async {
    final repository = _MutableRuntimeAgentStateRepository(_desktopState());
    final sender = _ApprovalSenderProbe();

    await _pumpShell(tester, repository: repository, sender: sender);

    await _tapSidebar(tester, 'Memory');
    expect(find.byKey(const ValueKey('desktop_memory_workbench_page')),
        findsOneWidget);
    expect(find.text('Memory Records'), findsOneWidget);
    expect(find.text('Task replies should use Chinese'), findsOneWidget);
    expect(find.text('Pending Candidates (1)'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('desktop_memory_candidate_approve_approval-memory-dark'),
      ),
    );
    await tester.pumpAndSettle();
    expect(sender.decisions,
        contains(('uid_1', 'approval-memory-dark', 'approve')));
    expect(repository.fetchCount, greaterThanOrEqualTo(2));

    await tester
        .tap(find.byKey(const ValueKey('desktop_memory_request_removal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('approval_required'), findsOneWidget);

    await _tapSidebar(tester, 'Approvals');
    expect(find.byKey(const ValueKey('desktop_approvals_workbench_page')),
        findsOneWidget);
    expect(find.text('Move 完成周报 to today 20:00'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop_approval_queue_approval-task-due')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop_approval_approve')));
    await tester.pumpAndSettle();
    expect(
        sender.decisions, contains(('uid_1', 'approval-task-due', 'approve')));

    await _tapSidebar(tester, 'Connectors');
    expect(find.byKey(const ValueKey('desktop_connectors_workbench_page')),
        findsOneWidget);
    expect(find.text('Email Binding'), findsOneWidget);
    expect(find.text('draft_only'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop_connector_calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Calendar Binding'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop_connector_primary_calendar')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('configure Calendar'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('desktop_connector_test_draft')));
    await tester.pumpAndSettle();
    expect(find.textContaining('draft-only'), findsOneWidget);
  });

  testWidgets('mobile bottom nav remains the five canonical entries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            conversationTabBuilder: (_, __) => const SizedBox(),
            reviewTabBuilder: (_, __) => const SizedBox(),
            notesTabBuilder: (_, __) => const SizedBox(),
            memoryTabBuilder: (_, __) => const SizedBox(),
            settingsTabBuilder: (_, __) => const SizedBox(),
            desktopMemoryBuilder: (_, __) => const SizedBox(),
            desktopApprovalsBuilder: (_, __) => const SizedBox(),
            desktopConnectorsBuilder: (_, __) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app_shell_bottom_nav')), findsOneWidget);
    expect(find.text('Briefing'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Memory'), findsNothing);
    expect(find.text('Approvals'), findsNothing);
    expect(find.text('Connectors'), findsNothing);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required _MutableRuntimeAgentStateRepository repository,
  required _ApprovalSenderProbe sender,
}) async {
  await tester.binding.setSurfaceSize(const Size(2560, 2048));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: AppShell(
          conversationTabBuilder: (_, __) => const SizedBox(),
          reviewTabBuilder: (_, __) => const SizedBox(),
          notesTabBuilder: (_, __) => const SizedBox(),
          memoryTabBuilder: (_, __) => const SizedBox(),
          settingsTabBuilder: (_, __) => const SizedBox(),
          desktopMemoryBuilder: (_, __) => DesktopMemoryWorkbenchPage(
            runtimeAgentStateRepository: repository,
            approvalSender: sender,
            vaultId: 'uid_1',
          ),
          desktopApprovalsBuilder: (_, __) => DesktopApprovalsWorkbenchPage(
            runtimeAgentStateRepository: repository,
            approvalSender: sender,
            vaultId: 'uid_1',
          ),
          desktopConnectorsBuilder: (_, __) => DesktopConnectorsWorkbenchPage(
            runtimeAgentStateRepository: repository,
            vaultId: 'uid_1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSidebar(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byKey(const ValueKey('app_shell_sidebar')),
    matching: find.text(label),
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

RuntimeAgentState _desktopState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': 'Research answer with citations.',
        'tool_trace': {
          'skill': 'web-research',
          'status': 'executed',
        },
        'created_at_ms': 1780292701000,
      },
    ],
    'working_set_records': [],
    'tasks': [],
    'memory_records': [
      {
        'id': 'mem-zh',
        'kind': 'memory',
        'title': 'Task replies should use Chinese',
        'body':
            'The user prefers all task-related responses and summaries to be in Simplified Chinese.',
        'status': 'active',
        'source': 'Chat',
        'source_message_id': 'MSG-88291',
        'confidence_percent': 99,
        'context_snapshot_id': 'CTX-9921',
        'updated_at_ms': 1780292701000,
      },
      {
        'id': 'mem-meetings',
        'kind': 'memory',
        'title': 'No meetings before 9 AM',
        'body': 'Avoid scheduling meetings before 9 AM unless approved.',
        'status': 'active',
        'source': 'Prefs',
        'updated_at_ms': 1780289101000,
      },
    ],
    'recurring_reminder_rules': [],
    'approval_items': [
      {
        'id': 'approval-memory-dark',
        'kind': 'memory_confirmation',
        'title': 'User prefers dark mode for presentations',
        'record': {
          'memory_text': 'User prefers dark mode for presentations',
          'risk': 'low',
        },
      },
      {
        'id': 'approval-task-due',
        'kind': 'task_mutation_confirmation',
        'title': 'Move 完成周报 to today 20:00',
        'task_id': 'T-88291',
        'source_intent_id': 'MSG-9012',
        'record': {
          'task_title': '完成周报',
          'before': 'due_date: "2026-06-12T09:00:00Z"',
          'after': 'due_date: "2026-06-12T20:00:00Z"',
          'reason': 'Rescheduled after a morning conflict.',
          'risk': 'medium',
        },
      },
      {
        'id': 'approval-payment',
        'kind': 'purchase_payment_refusal',
        'title': 'Send \$50 to Vendor',
        'record': {
          'status': 'refused',
          'blocked_action': 'payment',
        },
      },
    ],
    'recent_entity_refs': [
      {
        'entity_type': 'task',
        'title': '完成周报',
      },
    ],
    'latest_context_snapshot': {
      'id': 'CTX-9921',
      'generated_at_ms': 1780292701000,
      'packet': {
        'tool_trace': 'web-research',
      },
    },
    'audit_refs': [
      {'id': 'AUD-1'}
    ],
  });
}

final class _MutableRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _MutableRuntimeAgentStateRepository(this.state);

  RuntimeAgentState state;
  int fetchCount = 0;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    fetchCount += 1;
    return state;
  }
}

final class _ApprovalSenderProbe implements ChatRuntimeApprovalSender {
  final List<(String, String, String)> decisions = <(String, String, String)>[];

  @override
  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals({
    required String vaultId,
  }) async {
    return const <SecretaryRuntimeApprovalItem>[];
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
  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String approvalId,
    required String decision,
  }) async {
    decisions.add((vaultId, approvalId, decision));
    return null;
  }
}
