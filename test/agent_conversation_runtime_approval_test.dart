import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
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
import 'package:secondloop/core/models/platform_int.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'managed pro approval card applies approved task reschedule locally',
    (tester) async {
      final backend = _RuntimeApprovalBackend(
        initialTodos: [
          _RuntimeApprovalBackend.todo(id: 'task-1', title: '完成周报'),
        ],
      );
      final sender = _ApprovalRuntimeConversationSender(
        pendingResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-pending',
          'conversation_id': 'loop_home',
          'assistant': {'content': '好的，已为您准备好将“完成周报”的时间调整为今天 20:00 的申请。'},
          'metadata': {
            'run_id': 'run-pending',
            'turn_id': 'turn-pending',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'formal_mutation_pending',
            'run_status': 'waiting_for_approval',
            'approval_required': true,
            'applied_mutations': [],
            'approval_items': [
              {
                'id': 'approval-task-1',
                'task_id': 'task-1',
                'title': '完成周报',
                'kind': 'task_mutation_confirmation',
                'record': {
                  'id': 'task-1',
                  'due_at_ms': 1765454400000,
                  'status': 'todo',
                },
              },
            ],
          },
        }),
        approvedResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-approved',
          'conversation_id': 'loop_home',
          'assistant': {'content': '已批准并更新“完成周报”的时间。'},
          'metadata': {
            'run_id': 'run-approved',
            'turn_id': 'turn-approved',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'assistant_message',
            'run_status': 'completed',
            'approval_required': false,
            'applied_mutations': [
              {
                'entity_type': 'task',
                'mutation_type': 'reschedule',
                'status': 'applied',
                'record_id': 'task-1',
                'record': {
                  'id': 'task-1',
                  'due_at_ms': 1765454400000,
                  'status': 'todo',
                },
              },
            ],
          },
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
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
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '把“完成周报”改到今天 20:00，但不要标记完成。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('approval_preview_card')), findsOneWidget);
      var todo = (await backend.listTodos(Uint8List(32))).single;
      expect(platformIntToNullableInt(todo.dueAtMs), isNull);
      expect(todo.status, 'open');

      await tester.tap(find.text('Review & Approve'));
      await tester.pumpAndSettle();

      expect(sender.approvalDecisions, ['approval-task-1:approve']);
      expect(backend.transitionTodoCalls, 1);
      todo = (await backend.listTodos(Uint8List(32))).single;
      expect(platformIntToNullableInt(todo.dueAtMs), 1765454400000);
      expect(todo.status, 'open');
      expect(find.byKey(const ValueKey('approval_preview_card')), findsNothing);
    },
  );

  testWidgets(
    'managed pro approval card loads pending task reschedule from queue',
    (tester) async {
      final backend = _RuntimeApprovalBackend(
        initialTodos: [
          _RuntimeApprovalBackend.todo(id: 'task-1', title: '完成周报'),
        ],
      );
      final sender = _ApprovalRuntimeConversationSender(
        pendingResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-pending',
          'conversation_id': 'loop_home',
          'assistant': {'content': '好的，我已为您准备好将任务“完成周报”的时间调整为今天 20:00 的申请。'},
          'metadata': {
            'run_id': 'run-pending',
            'turn_id': 'turn-pending',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'formal_mutation_pending',
            'run_status': 'waiting_for_approval',
            'approval_required': true,
            'applied_mutations': [],
            'approval_items': [],
          },
        }),
        approvedResult: null,
        queuedApprovalItems: const [
          SecretaryRuntimeApprovalItem(
            id: 'approval-task-1',
            taskId: 'task-1',
            title: '完成周报',
            kind: 'task_mutation_confirmation',
            record: {
              'id': 'task-1',
              'title': '完成周报',
              'due_time': '20:00',
              'status': 'open',
            },
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
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
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '把“完成周报”改到今天 20:00，但不要标记完成。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.approvalFetches, ['uid_1']);
      expect(
          find.byKey(const ValueKey('approval_preview_card')), findsOneWidget);
      var todo = (await backend.listTodos(Uint8List(32))).single;
      expect(platformIntToNullableInt(todo.dueAtMs), isNull);
      expect(todo.status, 'open');

      final beforeApprove = DateTime.now();
      await tester.tap(find.text('Review & Approve'));
      await tester.pumpAndSettle();

      expect(sender.approvalDecisions, ['approval-task-1:approve']);
      todo = (await backend.listTodos(Uint8List(32))).single;
      final dueAt = DateTime.fromMillisecondsSinceEpoch(
        platformIntToNullableInt(todo.dueAtMs)!,
      );
      expect(dueAt.year, beforeApprove.year);
      expect(dueAt.month, beforeApprove.month);
      expect(dueAt.day, beforeApprove.day);
      expect(dueAt.hour, 20);
      expect(dueAt.minute, 0);
      expect(todo.status, 'open');
    },
  );

  testWidgets(
    'managed pro approval card remains visible after assistant reply',
    (tester) async {
      final backend = _RuntimeApprovalBackend(
        initialMessages: [
          for (var index = 0; index < 14; index++) ...[
            Message(
              id: 'old-user-$index',
              conversationId: 'loop_home',
              role: 'user',
              content: '历史消息 $index',
              createdAtMs: index * 2,
              isMemory: true,
            ),
            Message(
              id: 'old-assistant-$index',
              conversationId: 'loop_home',
              role: 'assistant',
              content: '历史回复 $index',
              createdAtMs: index * 2 + 1,
              isMemory: true,
            ),
          ],
        ],
        initialTodos: [
          _RuntimeApprovalBackend.todo(id: 'task-1', title: '完成周报'),
        ],
      );
      final sender = _ApprovalRuntimeConversationSender(
        pendingResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-pending',
          'conversation_id': 'loop_home',
          'assistant': {'content': '好的，我已为您准备好将任务“完成周报”的时间调整为今天 20:00 的申请。'},
          'metadata': {
            'run_id': 'run-pending',
            'turn_id': 'turn-pending',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'formal_mutation_pending',
            'run_status': 'waiting_for_approval',
            'approval_required': true,
            'applied_mutations': [],
          },
        }),
        approvedResult: null,
        queuedApprovalItems: const [
          SecretaryRuntimeApprovalItem(
            id: 'approval-task-1',
            taskId: 'task-1',
            title: '完成周报',
            kind: 'task_mutation_confirmation',
            record: {
              'id': 'task-1',
              'title': '完成周报',
              'due_time': '20:00',
              'status': 'open',
            },
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(1012, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
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
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '把“完成周报”改到今天 20:00，但不要标记完成。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.approvalFetches, ['uid_1']);
      expect(
        find.byKey(const ValueKey('approval_preview_card')),
        findsOneWidget,
      );
      expect(find.text('Review & Approve'), findsOneWidget);
      expect(find.text('Review & Approve').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'managed pro renders memory approvals as memory candidate cards',
    (tester) async {
      final backend = _RuntimeApprovalBackend();
      final sender = _ApprovalRuntimeConversationSender(
        pendingResult: SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-memory',
          'conversation_id': 'loop_home',
          'assistant': {'content': '我准备了两条记忆候选，保存前需要确认。'},
          'metadata': {
            'run_id': 'run-memory',
            'turn_id': 'turn-memory',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'memory_candidate',
            'run_status': 'waiting_for_approval',
            'approval_required': true,
            'applied_mutations': [],
            'approval_items': [
              {
                'id': 'approval-memory-meeting',
                'title': '我上午 9 点前不开会',
                'kind': 'memory_confirmation',
                'record': {
                  'id': 'memory-meeting',
                  'text': '我上午 9 点前不开会',
                },
              },
              {
                'id': 'approval-memory-language',
                'title': '任务回复请使用中文',
                'kind': 'memory_confirmation',
                'record': {
                  'id': 'memory-language',
                  'text': '任务回复请使用中文',
                },
              },
            ],
          },
        }),
        approvedResult: null,
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
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
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '记住：我上午 9 点前不开会。记住：任务回复请使用中文。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('approval_preview_card')), findsNothing);
      expect(
        find.byKey(
          const ValueKey(
            'runtime_memory_candidate_card_approval-memory-meeting',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'runtime_memory_candidate_card_approval-memory-language',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Memory suggestion'), findsNWidgets(2));
      expect(find.text('我上午 9 点前不开会'), findsWidgets);
      expect(find.text('任务回复请使用中文'), findsWidgets);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey(
              'runtime_memory_candidate_card_approval-memory-meeting',
            ),
          ),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey(
              'runtime_memory_candidate_card_approval-memory-language',
            ),
          ),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(sender.approvalDecisions, [
        'approval-memory-meeting:approve',
        'approval-memory-language:approve',
      ]);
      expect(
        find.byKey(
          const ValueKey(
            'runtime_memory_candidate_card_approval-memory-meeting',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'runtime_memory_candidate_card_approval-memory-language',
          ),
        ),
        findsNothing,
      );
      final pages = await backend.listMemoryPages(Uint8List(32));
      expect(pages.map((page) => page.title), [
        '我上午 9 点前不开会',
        '任务回复请使用中文',
      ]);
      expect(find.text('我上午 9 点前不开会'), findsWidgets);
      expect(find.text('任务回复请使用中文'), findsWidgets);
    },
  );
}

final class _RuntimeApprovalBackend extends TestAppBackend
    implements SecretaryBackend {
  _RuntimeApprovalBackend({
    super.initialMessages,
    List<Todo> initialTodos = const <Todo>[],
  })  : _todos = <String, Todo>{
          for (final todo in initialTodos) todo.id: todo,
        },
        _proposals = <String, SecretaryMemoryProposalRecord>{},
        _pages = <String, MemoryPageRecord>{};

  final Map<String, Todo> _todos;
  final Map<String, SecretaryMemoryProposalRecord> _proposals;
  final Map<String, MemoryPageRecord> _pages;
  int transitionTodoCalls = 0;

  static Todo todo({
    required String id,
    required String title,
    String status = 'open',
    int? dueAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: status,
      sourceEntryId: null,
      createdAtMs: platformIntFromInt(1000),
      updatedAtMs: platformIntFromInt(1000),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
      manualImportanceNudgeScore: platformIntFromInt(0),
      manualUrgencyNudgeScore: platformIntFromInt(0),
    );
  }

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    throw StateError('managed_pro_should_use_secretary_runtime');
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return _todos.values.toList(growable: false);
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    return _todos[todoId];
  }

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
    final current = _todos[id];
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId ?? current?.sourceEntryId,
      createdAtMs: current?.createdAtMs ?? platformIntFromInt(1000),
      updatedAtMs: platformIntFromInt(
        platformIntToNullableInt(current?.updatedAtMs) == null
            ? 1000
            : platformIntToInt(current!.updatedAtMs) + 1,
      ),
      reviewStage: reviewStage == null
          ? current?.reviewStage
          : platformIntFromInt(reviewStage),
      nextReviewAtMs: nextReviewAtMs == null
          ? current?.nextReviewAtMs
          : platformIntFromInt(nextReviewAtMs),
      lastReviewAtMs: lastReviewAtMs == null
          ? current?.lastReviewAtMs
          : platformIntFromInt(lastReviewAtMs),
      manualImportanceNudgeScore: manualImportanceNudgeScore == null
          ? current?.manualImportanceNudgeScore
          : platformIntFromInt(manualImportanceNudgeScore),
      manualUrgencyNudgeScore: manualUrgencyNudgeScore == null
          ? current?.manualUrgencyNudgeScore
          : platformIntFromInt(manualUrgencyNudgeScore),
    );
    _todos[id] = todo;
    return todo;
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
    transitionTodoCalls += 1;
    final current = _todos[todoId];
    if (current == null) {
      throw StateError('Missing todo $todoId');
    }
    final currentDueAtMs = platformIntToNullableInt(current.dueAtMs);
    final updated = Todo(
      id: current.id,
      title: current.title,
      dueAtMs: clearDueAtMs
          ? null
          : (dueAtMs ?? currentDueAtMs) == null
              ? null
              : platformIntFromInt((dueAtMs ?? currentDueAtMs)!),
      status: newStatus ?? current.status,
      sourceEntryId: current.sourceEntryId,
      createdAtMs: current.createdAtMs,
      updatedAtMs: platformIntFromInt(
        platformIntToInt(current.updatedAtMs) + 1,
      ),
      reviewStage: current.reviewStage,
      nextReviewAtMs: current.nextReviewAtMs,
      lastReviewAtMs: current.lastReviewAtMs,
      manualImportanceNudgeScore: current.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: current.manualUrgencyNudgeScore,
    );
    _todos[todoId] = updated;
    return updated;
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
    final id = 'proposal-${_proposals.length + 1}';
    final proposal = SecretaryMemoryProposalRecord(
      id: id,
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      state: 'pending',
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _proposals[id] = proposal;
    return proposal;
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    final proposal = _proposals[proposalId];
    if (proposal == null) throw StateError('Missing proposal $proposalId');
    final page = MemoryPageRecord(
      pageId: 'page-${_pages.length + 1}',
      pageType: 'memory',
      state: 'active',
      sourceCount: platformIntFromInt(
        proposal.sourceMessageId == null ? 0 : 1,
      ),
      title: proposal.title,
      summary: proposal.body,
      body: proposal.body,
      primaryEvidenceJson: proposal.sourceRefsJson ?? '[]',
      sourceDocumentIdsJson: proposal.sourceMessageId == null
          ? '[]'
          : '["${proposal.sourceMessageId}"]',
      confidenceLevel: proposal.confidence,
      humanCorrected: false,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _pages[page.pageId] = page;
    return page;
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    return _pages.values
        .where((page) => state == null || page.state == state)
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ApprovalRuntimeConversationSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  _ApprovalRuntimeConversationSender({
    required this.pendingResult,
    required this.approvedResult,
    this.queuedApprovalItems = const <SecretaryRuntimeApprovalItem>[],
  });

  final SecretaryRuntimeConversationResult pendingResult;
  final SecretaryRuntimeConversationResult? approvedResult;
  final List<SecretaryRuntimeApprovalItem> queuedApprovalItems;
  final List<String> sentMessages = <String>[];
  final List<String> approvalFetches = <String>[];
  final List<String> approvalDecisions = <String>[];
  final List<String> approvalPatches = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    sentMessages.add(message);
    return pendingResult;
  }

  @override
  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String approvalId,
    required String decision,
  }) async {
    approvalDecisions.add('$approvalId:$decision');
    return approvedResult;
  }

  @override
  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals({
    required String vaultId,
  }) async {
    approvalFetches.add(vaultId);
    return queuedApprovalItems;
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
      recurringRuleId: approvalId.replaceFirst('approval-', ''),
      editableFields: const ['title'],
      version: baseVersion + 1,
      record: <String, Object?>{
        'id': approvalId.replaceFirst('approval-', ''),
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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
