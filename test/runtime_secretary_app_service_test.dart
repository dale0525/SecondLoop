import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/cloud/runtime_secretary_app_service.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

import 'test_backend.dart';

void main() {
  test('runtime secretary app service persists applied task creations',
      () async {
    final backend = _TodoRecordingBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-1',
        'conversation_id': 'loop_home',
        'assistant': {'content': '好的，已为您创建任务：完成周报。'},
        'metadata': {
          'run_id': 'run-1',
          'turn_id': 'turn-1',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'task_created',
          'run_status': 'completed',
          'approval_required': false,
          'applied_mutations': [
            {
              'entity_type': 'task',
              'mutation_type': 'create',
              'status': 'applied',
              'record_id': 'task-1',
              'record': {
                'id': 'task-1',
                'title': '完成周报',
                'status': 'todo',
              },
            },
          ],
        },
      }),
    );
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    final result = await service.sendAndApply(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '帮我创建一个任务：完成周报。',
      sourceMessageId: 'm-user-1',
    );

    expect(sender.sentMessages, ['帮我创建一个任务：完成周报。']);
    expect(result.assistantContent, '好的，已为您创建任务：完成周报。');
    expect(
      (await backend.listMessages(
        Uint8List.fromList(List<int>.filled(32, 1)),
        'loop_home',
      ))
          .where((message) => message.role == 'assistant')
          .single
          .content,
      '好的，已为您创建任务：完成周报。',
    );
    final todos = await backend.listTodos(
      Uint8List.fromList(List<int>.filled(32, 1)),
    );
    expect(todos.single.id, 'task-1');
    expect(todos.single.title, '完成周报');
    expect(todos.single.status, 'open');
    expect(todos.single.sourceEntryId, 'm-user-1');
  });

  test(
      'runtime secretary app service stores web research citations as evidence',
      () async {
    final backend = _CitationRecordingBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-web-research',
        'conversation_id': 'loop_home',
        'assistant': {
          'content':
              'Apple 发布了 iPhone 17。[Apple Newsroom](https://www.apple.com/newsroom/)',
        },
        'metadata': {
          'run_id': 'run-web-research',
          'turn_id': 'turn-web-research',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
          'web_research_drafts': [
            {
              'query': 'Apple 今天的发布会发布了哪些产品？',
              'summary': 'Apple 发布了 iPhone 17。',
              'citations': [
                {
                  'title': 'Apple Newsroom',
                  'url': 'https://www.apple.com/newsroom/',
                  'domain': 'www.apple.com',
                  'fetched_at_ms': 1700000000000,
                },
              ],
            },
          ],
        },
      }),
    );
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await service.sendAndApply(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '查一下最近 Apple 发布会有哪些新产品，给我带来源。',
      sourceMessageId: 'm-user-search',
    );

    expect(backend.assistantCitationWrites, hasLength(1));
    final decoded = jsonDecode(backend.assistantCitationWrites.single)
        as Map<String, dynamic>;
    final sources = decoded['direct_sources'] as List<dynamic>;
    expect(sources, hasLength(1));
    expect(sources.single,
        containsPair('href', 'https://www.apple.com/newsroom/'));
    expect(sources.single, containsPair('title', 'Apple Newsroom'));
    expect(sources.single, containsPair('source_type', 'web_research'));
  });

  test('runtime secretary app service ignores pending task mutations',
      () async {
    final backend = _TodoRecordingBackend(
      initialTodos: [
        _TodoRecordingBackend.todo(id: 'task-1', title: '完成周报'),
      ],
    );
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-2',
        'conversation_id': 'loop_home',
        'assistant': {'content': '需要确认后再修改。'},
        'metadata': {
          'run_id': 'run-2',
          'turn_id': 'turn-2',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'formal_mutation_pending',
          'run_status': 'waiting_for_approval',
          'approval_required': true,
          'proposed_mutations': [
            {
              'entity_type': 'task',
              'mutation_type': 'reschedule',
              'status': 'pending_approval',
              'record': {
                'id': 'task-1',
                'title': '完成周报',
                'due_at_ms': 1765454400000,
              },
            },
          ],
          'applied_mutations': [],
        },
      }),
    );
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await service.sendAndApply(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '把“完成周报”改到今天 20:00',
      sourceMessageId: 'm-user-2',
    );

    final todo = (await backend.listTodos(
      Uint8List.fromList(List<int>.filled(32, 1)),
    ))
        .single;
    expect(todo.title, '完成周报');
    expect(platformIntToNullableInt(todo.dueAtMs), isNull);
    expect(todo.status, 'open');
  });

  test('runtime secretary app service applies approved task mutation records',
      () async {
    final backend = _TodoRecordingBackend(
      initialTodos: [
        _TodoRecordingBackend.todo(id: 'task-1', title: '完成周报'),
      ],
    );
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-2',
        'conversation_id': 'loop_home',
        'assistant': {'content': '需要确认后再修改。'},
        'metadata': {
          'run_id': 'run-2',
          'turn_id': 'turn-2',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'formal_mutation_pending',
          'run_status': 'waiting_for_approval',
          'approval_required': true,
          'applied_mutations': [],
        },
      }),
    );
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await service.applyApprovedTaskMutation(
      const SecretaryRuntimeApprovalItem(
        id: 'approval-task-1',
        taskId: 'task-1',
        title: '完成周报',
        kind: 'task_mutation_confirmation',
        record: {
          'id': 'task-1',
          'title': '完成周报',
          'due_at_ms': 1765454400000,
          'status': 'todo',
        },
      ),
      sourceMessageId: 'approval-task-1',
    );

    final todo = (await backend.listTodos(
      Uint8List.fromList(List<int>.filled(32, 1)),
    ))
        .single;
    expect(todo.title, '完成周报');
    expect(platformIntToNullableInt(todo.dueAtMs), 1765454400000);
    expect(todo.status, 'open');
  });

  test('runtime secretary app service resolves approved due time records',
      () async {
    final backend = _TodoRecordingBackend(
      initialTodos: [
        _TodoRecordingBackend.todo(id: 'task-1', title: '完成周报'),
      ],
    );
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-2',
        'conversation_id': 'loop_home',
        'assistant': {'content': '需要确认后再修改。'},
        'metadata': {
          'run_id': 'run-2',
          'turn_id': 'turn-2',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'formal_mutation_pending',
          'run_status': 'waiting_for_approval',
          'approval_required': true,
          'applied_mutations': [],
        },
      }),
    );
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );
    final now = DateTime.now();

    await service.applyApprovedTaskMutation(
      const SecretaryRuntimeApprovalItem(
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
      sourceMessageId: 'approval-task-1',
    );

    final todo = (await backend.listTodos(
      Uint8List.fromList(List<int>.filled(32, 1)),
    ))
        .single;
    final dueAt = DateTime.fromMillisecondsSinceEpoch(
      platformIntToNullableInt(todo.dueAtMs)!,
    );
    expect(dueAt.year, now.year);
    expect(dueAt.month, now.month);
    expect(dueAt.day, now.day);
    expect(dueAt.hour, 20);
    expect(dueAt.minute, 0);
    expect(todo.status, 'open');
  });

  test('runtime secretary app service stores approved memory confirmations',
      () async {
    final backend = _MemoryRecordingBackend();
    final sender = _FakeApprovalRuntimeSender(approvedResult: null);
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: sessionKey,
    );

    await service.approveApprovalItem(
      const SecretaryRuntimeApprovalItem(
        id: 'approval-memory-meeting',
        taskId: '',
        title: '我上午 9 点前不开会',
        kind: 'memory_confirmation',
        record: {
          'id': 'memory-meeting',
          'text': '我上午 9 点前不开会',
        },
      ),
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      sourceMessageId: 'm-user-3',
    );

    expect(sender.approvalDecisions, ['approval-memory-meeting:approve']);
    final pages = await backend.listMemoryPages(sessionKey, state: 'active');
    expect(pages, hasLength(1));
    expect(pages.single.title, '我上午 9 点前不开会');
    expect(pages.single.summary, '我上午 9 点前不开会');
    expect(pages.single.body, '我上午 9 点前不开会');
    expect(pages.single.state, 'active');
  });

  test('runtime secretary app service stores approved recurring reminders',
      () async {
    final backend = _TodoRecordingBackend();
    final sender = _FakeApprovalRuntimeSender(approvedResult: null);
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: sessionKey,
    );

    await service.approveApprovalItem(
      const SecretaryRuntimeApprovalItem(
        id: 'approval-recurring-rule-child-birthday-gift',
        taskId: '',
        title: '提醒买礼物',
        kind: 'recurring_reminder_confirmation',
        recurringRuleId: 'recurring-rule-child-birthday-gift',
        record: {
          'kind': 'recurring_reminder_rule',
          'id': 'recurring-rule-child-birthday-gift',
          'title': '提醒买礼物',
          'next_fire_at_ms': 1780156800000,
          'schedule': {
            'type': 'yearly_relative_date',
            'source_memory_id': 'memory-child-birthday',
            'offset_days': -1,
          },
        },
      ),
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      sourceMessageId: 'm-user-birthday',
    );

    expect(sender.approvalDecisions, [
      'approval-recurring-rule-child-birthday-gift:approve',
    ]);
    final todos = await backend.listTodos(sessionKey);
    expect(todos, hasLength(1));
    expect(todos.single.id, 'todo:recurring-rule-child-birthday-gift');
    expect(todos.single.title, '提醒买礼物');
    expect(platformIntToNullableInt(todos.single.dueAtMs), 1780156800000);
    expect(todos.single.status, 'open');
    expect(todos.single.sourceEntryId, 'm-user-birthday');
    expect(
      backend.recurrenceRules['todo:recurring-rule-child-birthday-gift'],
      '{"freq":"yearly","interval":1}',
    );
  });

  test('runtime secretary app service patches approval item titles', () async {
    final backend = _TodoRecordingBackend();
    final sender = _FakeApprovalRuntimeSender(approvedResult: null);
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: sessionKey,
    );

    final updated = await service.patchApprovalItem(
      const SecretaryRuntimeApprovalItem(
        id: 'approval-recurring-rule-child-birthday-gift',
        taskId: '',
        title: '孩子生日',
        kind: 'recurring_reminder_confirmation',
        recurringRuleId: 'recurring-rule-child-birthday-gift',
        editableFields: ['title'],
        version: 1,
        record: {
          'id': 'recurring-rule-child-birthday-gift',
          'title': '孩子生日',
        },
      ),
      vaultId: 'managed-user-1',
      changes: const {'title': '给孩子买生日礼物'},
    );

    expect(sender.approvalPatches, [
      'approval-recurring-rule-child-birthday-gift:1:给孩子买生日礼物',
    ]);
    expect(updated.title, '给孩子买生日礼物');
    expect(updated.version, 2);
    expect(updated.record?['title'], '给孩子买生日礼物');
  });

  test('runtime secretary app service persists applied recurring reminders',
      () async {
    final backend = _TodoRecordingBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-recurring-applied',
        'conversation_id': 'loop_home',
        'assistant': {'content': '已创建每年生日前一天的提醒。'},
        'metadata': {
          'run_id': 'run-recurring-applied',
          'turn_id': 'turn-recurring-applied',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
          'applied_mutations': [
            {
              'entity_type': 'recurring_reminder_rule',
              'mutation_type': 'create',
              'status': 'applied',
              'record_id': 'recurring-rule-child-birthday-gift',
              'record': {
                'kind': 'recurring_reminder_rule',
                'id': 'recurring-rule-child-birthday-gift',
                'title': '提醒买礼物',
                'next_fire_at_ms': 1780156800000,
                'schedule': {
                  'type': 'yearly_relative_date',
                  'source_memory_id': 'memory-child-birthday',
                  'offset_days': -1,
                },
              },
            },
          ],
        },
      }),
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: sessionKey,
    );

    await service.sendAndApply(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '每年孩子生日前一天提醒我买礼物。',
      sourceMessageId: 'm-user-birthday',
    );

    final todos = await backend.listTodos(sessionKey);
    expect(todos, hasLength(1));
    expect(todos.single.title, '提醒买礼物');
    expect(platformIntToNullableInt(todos.single.dueAtMs), 1780156800000);
    expect(
      backend.recurrenceRules['todo:recurring-rule-child-birthday-gift'],
      '{"freq":"yearly","interval":1}',
    );
  });

  test('runtime secretary app service persists applied memory pages', () async {
    final backend = _MemoryRecordingBackend();
    final sender = _FakeRuntimeSender(
      result: SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-memory-applied',
        'conversation_id': 'loop_home',
        'assistant': {'content': '已记住：我下午 6 点后不接工作电话。'},
        'metadata': {
          'run_id': 'run-memory-applied',
          'turn_id': 'turn-memory-applied',
          'conversation_id': 'loop_home',
          'vault_id': 'managed-user-1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
          'applied_mutations': [
            {
              'entity_type': 'memory_page',
              'mutation_type': 'create',
              'status': 'applied',
              'record_id': 'memory-after-hours',
              'record': {
                'id': 'memory-after-hours',
                'title': '我下午 6 点后不接工作电话',
                'body': '我下午 6 点后不接工作电话。',
                'kind': 'preference',
              },
            },
          ],
        },
      }),
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final service = RuntimeSecretaryAppService(
      sender: sender,
      backend: backend,
      sessionKey: sessionKey,
    );

    await service.sendAndApply(
      vaultId: 'managed-user-1',
      conversationId: 'loop_home',
      message: '记住：我下午 6 点后不接工作电话。',
      sourceMessageId: 'm-user-4',
    );

    final pages = await backend.listMemoryPages(sessionKey, state: 'active');
    expect(pages, hasLength(1));
    expect(pages.single.title, '我下午 6 点后不接工作电话');
    expect(pages.single.body, '我下午 6 点后不接工作电话。');
    expect(pages.single.sourceCount, platformIntFromInt(1));
  });
}

final class _FakeRuntimeSender implements ChatRuntimeConversationSender {
  _FakeRuntimeSender({required this.result});

  final SecretaryRuntimeConversationResult result;
  final List<String> sentMessages = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    sentMessages.add(message);
    return result;
  }
}

final class _FakeApprovalRuntimeSender
    implements ChatRuntimeConversationSender, ChatRuntimeApprovalSender {
  _FakeApprovalRuntimeSender({required this.approvedResult});

  final SecretaryRuntimeConversationResult? approvedResult;
  final List<String> approvalDecisions = <String>[];
  final List<String> approvalPatches = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    throw StateError('send_not_expected');
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
    return const <SecretaryRuntimeApprovalItem>[];
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
      recurringRuleId: 'recurring-rule-child-birthday-gift',
      editableFields: const ['title'],
      version: baseVersion + 1,
      record: <String, Object?>{
        'id': 'recurring-rule-child-birthday-gift',
        'title': title,
      },
    );
  }
}

final class _TodoRecordingBackend extends TestAppBackend {
  _TodoRecordingBackend({List<Todo> initialTodos = const <Todo>[]})
      : _todos = <String, Todo>{
          for (final todo in initialTodos) todo.id: todo,
        };

  final Map<String, Todo> _todos;
  final Map<String, String> recurrenceRules = <String, String>{};
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
  Future<List<Todo>> listTodos(Uint8List key) async {
    return _todos.values.toList(growable: false);
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
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: platformIntFromInt(1000),
      updatedAtMs: platformIntFromInt(1000),
      reviewStage: reviewStage == null ? null : platformIntFromInt(reviewStage),
      nextReviewAtMs:
          nextReviewAtMs == null ? null : platformIntFromInt(nextReviewAtMs),
      lastReviewAtMs:
          lastReviewAtMs == null ? null : platformIntFromInt(lastReviewAtMs),
      manualImportanceNudgeScore: platformIntFromInt(
        manualImportanceNudgeScore ?? 0,
      ),
      manualUrgencyNudgeScore: platformIntFromInt(
        manualUrgencyNudgeScore ?? 0,
      ),
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
    final todo = Todo(
      id: current.id,
      title: current.title,
      dueAtMs: clearDueAtMs
          ? null
          : platformIntFromInt(
              dueAtMs ?? platformIntToNullableInt(current.dueAtMs) ?? 0,
            ),
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
    _todos[todoId] = todo;
    return todo;
  }

  @override
  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) async {
    recurrenceRules[todoId] = ruleJson;
  }
}

final class _CitationRecordingBackend extends _TodoRecordingBackend
    implements AssistantCitationWriteBackend {
  final List<String> assistantCitationWrites = <String>[];

  @override
  Future<Message> insertAssistantMessageWithCitations(
    Uint8List key,
    String conversationId, {
    required String content,
    String? citationsJson,
  }) async {
    assistantCitationWrites.add(citationsJson ?? '');
    return insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: content,
    );
  }
}

final class _MemoryRecordingBackend extends _TodoRecordingBackend
    implements SecretaryBackend {
  final Map<String, SecretaryMemoryProposalRecord> _proposals =
      <String, SecretaryMemoryProposalRecord>{};
  final Map<String, MemoryPageRecord> _pages = <String, MemoryPageRecord>{};

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
    if (proposal == null) {
      throw StateError('Missing proposal $proposalId');
    }
    final accepted = SecretaryMemoryProposalRecord(
      id: proposal.id,
      sourceMessageId: proposal.sourceMessageId,
      kind: proposal.kind,
      title: proposal.title,
      body: proposal.body,
      confidence: proposal.confidence,
      state: 'accepted',
      sourceRefsJson: proposal.sourceRefsJson,
      actionHint: proposal.actionHint,
      createdAtMs: proposal.createdAtMs,
      updatedAtMs: platformIntFromInt(nowMs),
      acceptedAtMs: platformIntFromInt(nowMs),
    );
    _proposals[proposalId] = accepted;
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
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    return _proposals.values
        .where((proposal) => state == null || proposal.state == state)
        .toList(growable: false);
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    final page = _pages[pageId];
    if (page == null) throw StateError('Missing memory page $pageId');
    return page;
  }

  @override
  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryRunRecord> createSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryToolCallRecord> createSecretaryToolCall(
    Uint8List key, {
    required String runId,
    required String toolName,
    required String status,
    required bool requiresConfirmation,
    String? inputJson,
    String? outputJson,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SecretaryToolCallRecord>> listSecretaryToolCallsForRun(
    Uint8List key, {
    required String runId,
  }) async {
    throw UnimplementedError();
  }
}
