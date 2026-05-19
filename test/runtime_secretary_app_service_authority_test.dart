import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/cloud/runtime_secretary_app_service.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';

void main() {
  test(
    'applyResult does not copy runtime task memory or recurring mutations into local stores',
    () async {
      final backend = _AuthorityBackend();
      final service = RuntimeSecretaryAppService(
        sender: _UnusedRuntimeSender(),
        backend: backend,
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      );

      await service.applyResult(
        SecretaryRuntimeConversationResult.fromJson(const {
          'run_id': 'run-1',
          'conversation_id': 'loop_home',
          'assistant': {'content': 'Runtime applied changes.'},
          'metadata': {
            'run_id': 'run-1',
            'turn_id': 'turn-1',
            'conversation_id': 'loop_home',
            'vault_id': 'uid_1',
            'response_type': 'task_created',
            'run_status': 'completed',
            'approval_required': false,
            'applied_mutations': [
              {
                'entity_type': 'task',
                'mutation_type': 'create',
                'status': 'applied',
                'record': {
                  'id': 'task-1',
                  'title': '完成周报',
                  'status': 'open',
                },
              },
              {
                'entity_type': 'memory',
                'mutation_type': 'create',
                'status': 'applied',
                'record': {
                  'id': 'memory-1',
                  'text': '任务回复请使用中文',
                },
              },
              {
                'entity_type': 'recurring_reminder_rule',
                'mutation_type': 'create',
                'status': 'applied',
                'record': {
                  'id': 'rule-1',
                  'title': '买礼物',
                  'next_fire_at_ms': 1700000000000,
                  'recurrence_rule': {'freq': 'yearly'},
                },
              },
            ],
          },
        }),
        conversationId: 'loop_home',
      );

      expect(backend.upsertTodoCalls, 0);
      expect(backend.transitionTodoCalls, 0);
      expect(backend.upsertTodoRecurrenceCalls, 0);
      expect(backend.createMemoryProposalCalls, 0);
      expect(backend.acceptMemoryProposalCalls, 0);
    },
  );
}

final class _AuthorityBackend extends TestAppBackend
    implements SecretaryBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  int upsertTodoCalls = 0;
  int transitionTodoCalls = 0;
  int upsertTodoRecurrenceCalls = 0;
  int createMemoryProposalCalls = 0;
  int acceptMemoryProposalCalls = 0;

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
    upsertTodoCalls += 1;
    throw StateError('upsertTodo should not be used');
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
    throw StateError('transitionTodo should not be used');
  }

  @override
  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) async {
    upsertTodoRecurrenceCalls += 1;
    throw StateError('upsertTodoRecurrence should not be used');
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
    createMemoryProposalCalls += 1;
    throw StateError('createSecretaryMemoryProposal should not be used');
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    acceptMemoryProposalCalls += 1;
    throw StateError('acceptSecretaryMemoryProposal should not be used');
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    throw StateError('listMemoryPages should not be used');
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
}

final class _UnusedRuntimeSender implements ChatRuntimeConversationSender {
  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    throw StateError('send should not be used');
  }
}
