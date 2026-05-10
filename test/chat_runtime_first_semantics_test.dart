import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('chat does not locally complete 完成周报 while rescheduling',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend(
      todos: const [
        Todo(
          id: 'task-1',
          title: '完成周报',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await _pumpChat(tester, backend);
    await _send(tester, '把“完成周报”改到今天 20:00。');
    await tester.pump(const Duration(milliseconds: 500));

    expect(backend.calls, isNot(contains('transitionTodo')));
    expect(backend.calls, isNot(contains('setTodoStatus')));
    expect(backend.calls, isNot(contains('upsertTodo')));
  });

  testWidgets('chat does not locally mutate priority for urgent task text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend(
      todos: const [
        Todo(
          id: 'task-1',
          title: '完成周报',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await _pumpChat(tester, backend);
    await _send(tester, '把“完成周报”标为紧急。');
    await tester.pump(const Duration(milliseconds: 500));

    expect(backend.calls, isNot(contains('transitionTodo')));
    expect(backend.calls, isNot(contains('setTodoStatus')));
    expect(backend.calls, isNot(contains('upsertTodo')));
  });

  testWidgets('chat does not create local memory proposals from remember text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend();

    await _pumpChat(tester, backend);
    await _send(
      tester,
      '记住：我上午 9 点前不开会。记住：任务回复请使用中文。',
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(backend.calls, isNot(contains('createSecretaryMemoryProposal')));
    expect(find.byKey(const ValueKey('secretary_memory_card')), findsNothing);
  });

  testWidgets('chat does not enqueue local semantic parse jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    final backend = _RuntimeFirstBackend();

    await _pumpChat(tester, backend);
    await _send(tester, '修电视机');
    await tester.pump(const Duration(milliseconds: 500));

    expect(backend.calls, isNot(contains('enqueueSemanticParseJob')));
  });

  testWidgets('chat sends user messages to secretary runtime', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult(
        runId: 'run-1',
        conversationId: 'loop_home',
        assistantContent: '待确认：改截止时间。',
        metadata: SecretaryRuntimeResponseMetadata(
          runId: 'run-1',
          turnId: 'turn-run-1',
          conversationId: 'loop_home',
          vaultId: 'loop_home',
          responseType: 'formal_mutation_pending',
          runStatus: 'waiting_for_approval',
          approvalRequired: true,
          proposedMutations: const <Map<String, Object?>>[],
          appliedMutations: const <Map<String, Object?>>[],
          approvalItems: const <SecretaryRuntimeApprovalItem>[],
        ),
      ),
    );

    await _pumpChat(tester, backend, runtimeConversationSender: sender);
    await _send(tester, '把“完成周报”改到今天 20:00。');
    await tester.pump(const Duration(milliseconds: 500));

    expect(sender.messages, ['把“完成周报”改到今天 20:00。']);
    expect(sender.conversationIds, ['loop_home']);
    expect(sender.vaultIds, ['loop_home']);
    expect(find.text('待确认：改截止时间。'), findsOneWidget);
  });

  testWidgets('chat task creation is rendered from runtime response',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult(
        runId: 'run-1',
        conversationId: 'loop_home',
        assistantContent: '已创建任务：完成周报。',
        metadata: SecretaryRuntimeResponseMetadata(
          runId: 'run-1',
          turnId: 'turn-run-1',
          conversationId: 'loop_home',
          vaultId: 'loop_home',
          responseType: 'task_created',
          runStatus: 'completed',
          approvalRequired: false,
          proposedMutations: const <Map<String, Object?>>[],
          appliedMutations: const <Map<String, Object?>>[
            {
              'entity_type': 'task',
              'mutation_type': 'create',
              'status': 'applied',
              'record_id': 'task-1',
            },
          ],
          approvalItems: const <SecretaryRuntimeApprovalItem>[],
        ),
      ),
    );

    await _pumpChat(tester, backend, runtimeConversationSender: sender);
    await _send(tester, '帮我创建一个任务：完成周报。');
    await tester.pump(const Duration(milliseconds: 500));

    expect(sender.messages, ['帮我创建一个任务：完成周报。']);
    expect(backend.calls, isNot(contains('upsertTodo')));
    expect(find.text('已创建任务：完成周报。'), findsOneWidget);
  });

  testWidgets('chat external email request is surfaced from runtime only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult(
        runId: 'run-1',
        conversationId: 'loop_home',
        assistantContent: '我可以先起草邮件；发送前需要连接邮箱并确认。',
        metadata: SecretaryRuntimeResponseMetadata(
          runId: 'run-1',
          turnId: 'turn-run-1',
          conversationId: 'loop_home',
          vaultId: 'loop_home',
          responseType: 'needs_configuration',
          runStatus: 'completed',
          approvalRequired: false,
          proposedMutations: const <Map<String, Object?>>[],
          appliedMutations: const <Map<String, Object?>>[],
          approvalItems: const <SecretaryRuntimeApprovalItem>[],
        ),
      ),
    );

    await _pumpChat(tester, backend, runtimeConversationSender: sender);
    await _send(tester, '直接把周报邮件发给 Alice。');
    await tester.pump(const Duration(milliseconds: 500));

    expect(sender.messages, ['直接把周报邮件发给 Alice。']);
    expect(backend.calls, isNot(contains('upsertTodo')));
    expect(backend.calls, isNot(contains('createSecretaryMemoryProposal')));
    expect(backend.calls, isNot(contains('enqueueSemanticParseJob')));
    expect(find.text('我可以先起草邮件；发送前需要连接邮箱并确认。'), findsOneWidget);
  });

  testWidgets('chat shows hosted runtime processing state while waiting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RuntimeFirstBackend();
    final resultCompleter = Completer<SecretaryRuntimeConversationResult>();
    final sender = _CompletingRuntimeSender(resultCompleter.future);

    await _pumpChat(tester, backend, runtimeConversationSender: sender);
    await _send(tester, '帮我创建一个任务：完成周报。');
    await sender.started.future;
    await tester.pump();

    final processingText = '${t.settings.runtimeMode.title}…';
    expect(
      find.byKey(const ValueKey('chat_runtime_secretary_processing')),
      findsOneWidget,
    );
    expect(find.text(processingText), findsWidgets);

    resultCompleter.complete(
      SecretaryRuntimeConversationResult(
        runId: 'run-1',
        conversationId: 'loop_home',
        assistantContent: '已创建任务：完成周报。',
        metadata: SecretaryRuntimeResponseMetadata(
          runId: 'run-1',
          turnId: 'turn-run-1',
          conversationId: 'loop_home',
          vaultId: 'loop_home',
          responseType: 'task_created',
          runStatus: 'completed',
          approvalRequired: false,
          proposedMutations: const <Map<String, Object?>>[],
          appliedMutations: const <Map<String, Object?>>[],
          approvalItems: const <SecretaryRuntimeApprovalItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat_runtime_secretary_processing')),
      findsNothing,
    );
    expect(find.text(processingText), findsNothing);
    expect(find.text('已创建任务：完成周报。'), findsOneWidget);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  AppBackend backend, {
  ChatRuntimeConversationSender? runtimeConversationSender,
}) async {
  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        home: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: AppBackendScope(
            backend: backend,
            child: ChatPage(
              runtimeConversationSender: runtimeConversationSender,
              conversation: const Conversation(
                id: 'loop_home',
                title: 'Loop',
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRuntimeSender implements ChatRuntimeConversationSender {
  _FakeRuntimeSender({required this.result});

  final SecretaryRuntimeConversationResult result;
  final List<String> vaultIds = <String>[];
  final List<String> conversationIds = <String>[];
  final List<String> messages = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    vaultIds.add(vaultId);
    conversationIds.add(conversationId);
    messages.add(message);
    return result;
  }
}

final class _CompletingRuntimeSender implements ChatRuntimeConversationSender {
  _CompletingRuntimeSender(this.result);

  final Future<SecretaryRuntimeConversationResult> result;
  final Completer<void> started = Completer<void>();

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    return result;
  }
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('chat_input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('chat_send')));
  await tester.pump();
}

final class _RuntimeFirstBackend extends TestAppBackend {
  _RuntimeFirstBackend({List<Todo> todos = const <Todo>[]})
      : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;
  final List<String> calls = <String>[];

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      List<Todo>.from(_todos, growable: false);

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    calls.add('upsertTodo');
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 1,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ?? 0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ?? 0,
    );
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    calls.add('setTodoStatus');
    return _todos.first;
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    calls.add('transitionTodo');
    return _todos.first;
  }

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('enqueueSemanticParseJob');
  }

  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    calls.add('createSecretaryMemoryProposal');
    return SecretaryMemoryProposalRecord(
      id: 'memory-proposal-1',
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      state: 'pending',
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async =>
      const <SecretaryMemoryProposalRecord>[];

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async =>
      const <MemoryPageRecord>[];
}
