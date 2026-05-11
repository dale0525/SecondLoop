import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_secretary_app_service.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

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

final class _TodoRecordingBackend extends TestAppBackend {
  _TodoRecordingBackend({List<Todo> initialTodos = const <Todo>[]})
      : _todos = <String, Todo>{
          for (final todo in initialTodos) todo.id: todo,
        };

  final Map<String, Todo> _todos;

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
}
