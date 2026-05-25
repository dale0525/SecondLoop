import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/features/agent_ui/desktop_approvals_workbench_page.dart';

void main() {
  testWidgets(
    'pending queue keeps actionable blocked and configuration items visible',
    (tester) async {
      final repository = _MutableRuntimeAgentStateRepository(_approvalsState());
      final sender = _ApprovalSenderProbe();

      await _pumpApprovals(tester, repository: repository, sender: sender);

      expect(find.text('Task due change'), findsOneWidget);
      expect(
          find.text('Email connector needs reauthorization'), findsOneWidget);
      expect(find.text(r'Send $50 to Vendor'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('desktop_approval_queue_approval-email')),
      );
      await tester.pumpAndSettle();

      expect(find.text('needs_configuration'), findsWidgets);
      expect(_approveButton(tester).onPressed, isNull);
      expect(_rejectButton(tester).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('desktop_approval_queue_approval-payment')),
      );
      await tester.pumpAndSettle();

      expect(find.text('refused'), findsWidgets);
      expect(_approveButton(tester).onPressed, isNull);
      expect(_rejectButton(tester).onPressed, isNull);
      expect(sender.decisions, isEmpty);
    },
  );

  testWidgets('selecting a queue item updates the diff detail', (tester) async {
    final repository = _MutableRuntimeAgentStateRepository(_approvalsState());

    await _pumpApprovals(
      tester,
      repository: repository,
      sender: _ApprovalSenderProbe(),
    );

    expect(find.text('due_date: "2026-06-12T09:00:00Z"'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop_approval_queue_approval-memory')),
    );
    await tester.pumpAndSettle();

    expect(find.text('previous value not reported'), findsOneWidget);
    expect(find.text('User prefers concise meeting notes'), findsWidgets);
  });

  testWidgets('approve and reject submit runtime decisions and refresh',
      (tester) async {
    final repository = _MutableRuntimeAgentStateRepository(_approvalsState());
    final sender = _ApprovalSenderProbe();

    await _pumpApprovals(tester, repository: repository, sender: sender);

    await tester.tap(
      find.byKey(const ValueKey('desktop_approval_queue_approval-task')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('desktop_approval_approve')));
    await tester.pumpAndSettle();
    expect(sender.decisions, contains(('uid_1', 'approval-task', 'approve')));
    expect(repository.fetchCount, greaterThanOrEqualTo(2));

    await tester.tap(find.byKey(const ValueKey('desktop_approval_reject')));
    await tester.pumpAndSettle();
    expect(sender.decisions, contains(('uid_1', 'approval-task', 'reject')));
    expect(repository.fetchCount, greaterThanOrEqualTo(3));
  });

  testWidgets('empty and fetch-error states are explicit and retryable',
      (tester) async {
    final repository = _MutableRuntimeAgentStateRepository(
      RuntimeAgentState.empty(vaultId: 'uid_1', conversationId: 'loop_home'),
    );

    await _pumpApprovals(
      tester,
      repository: repository,
      sender: _ApprovalSenderProbe(),
    );

    expect(find.text('No matching approvals'), findsOneWidget);

    repository
      ..state = _approvalsState()
      ..error = StateError('offline approvals');

    await tester.tap(find.byKey(const ValueKey('desktop_approvals_refresh')));
    await tester.pumpAndSettle();

    expect(find.textContaining('offline approvals'), findsOneWidget);

    repository.error = null;
    await tester.tap(find.byKey(const ValueKey('desktop_approval_retry')));
    await tester.pumpAndSettle();

    expect(find.text('Task due change'), findsOneWidget);
    expect(repository.fetchCount, greaterThanOrEqualTo(3));
  });
}

Future<void> _pumpApprovals(
  WidgetTester tester, {
  required _MutableRuntimeAgentStateRepository repository,
  required _ApprovalSenderProbe sender,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DesktopApprovalsWorkbenchPage(
          runtimeAgentStateRepository: repository,
          approvalSender: sender,
          vaultId: 'uid_1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FilledButton _approveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const ValueKey('desktop_approval_approve')),
  );
}

OutlinedButton _rejectButton(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.byKey(const ValueKey('desktop_approval_reject')),
  );
}

RuntimeAgentState _approvalsState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [],
    'working_set_records': [],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [
      {
        'id': 'approval-task',
        'kind': 'task_mutation_confirmation',
        'title': 'Task due change',
        'task_id': 'T-88291',
        'source_intent_id': 'MSG-9012',
        'record': {
          'task_title': 'Weekly report',
          'before': 'due_date: "2026-06-12T09:00:00Z"',
          'after': 'due_date: "2026-06-12T20:00:00Z"',
          'reason': 'Rescheduled after a morning conflict.',
          'source_excerpt': 'Push the weekly report to tonight, around 8pm.',
          'risk': 'medium',
        },
      },
      {
        'id': 'approval-memory',
        'kind': 'memory_confirmation',
        'title': 'User prefers concise meeting notes',
        'record': {
          'memory_text': 'User prefers concise meeting notes',
          'risk': 'low',
        },
      },
      {
        'id': 'approval-email',
        'kind': 'email_draft_confirmation',
        'title': 'Email connector needs reauthorization',
        'record': {
          'status': 'needs_configuration',
          'connector': 'email',
          'risk': 'high',
        },
      },
      {
        'id': 'approval-payment',
        'kind': 'purchase_payment_refusal',
        'title': r'Send $50 to Vendor',
        'record': {
          'status': 'refused',
          'blocked_action': 'payment',
          'risk': 'high',
        },
      },
    ],
    'recent_entity_refs': [
      {'entity_type': 'task', 'title': 'Weekly report'},
    ],
    'latest_context_snapshot': null,
    'audit_refs': [
      {'id': 'AUD-1'},
    ],
  });
}

final class _MutableRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _MutableRuntimeAgentStateRepository(this.state);

  RuntimeAgentState state;
  Object? error;
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
    final currentError = error;
    if (currentError != null) throw currentError;
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
