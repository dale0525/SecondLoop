import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/cloud/runtime_secretary_app_service.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';

void main() {
  test('runtime-first app paths do not swallow UnsupportedError', () {
    final files = [
      File('lib/features/agent_ui/agent_conversation_page.dart'),
      File('lib/core/cloud/runtime_secretary_app_service.dart'),
      File('lib/core/cloud/runtime_secretary_app_service_memory.dart'),
      File('lib/web_app/web_initial_sync_gate.dart'),
    ].where((file) => file.existsSync());

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('on UnsupportedError')),
        reason: '${file.path} must expose unsupported backend capabilities',
      );
      expect(
        source,
        isNot(contains('on UnimplementedError')),
        reason: '${file.path} must expose unimplemented backend capabilities',
      );
      expect(
        source,
        isNot(contains('runtime_first_native_runtime_removed')),
        reason: '${file.path} must not special-case retired backend stubs',
      );
    }
  });

  test('runtime memory dedupe exposes unsupported backend capability',
      () async {
    final backend = _UnsupportedMemoryBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
    final result = SecretaryRuntimeConversationResult.fromJson(const {
      'run_id': 'run-memory-unsupported',
      'conversation_id': 'loop_home',
      'assistant': {'content': '已记住。'},
      'metadata': {
        'run_id': 'run-memory-unsupported',
        'turn_id': 'turn-memory-unsupported',
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
              'title': 'After-hours calls',
              'body': 'I do not take work calls after 6 PM.',
              'kind': 'preference',
            },
          },
        ],
      },
    });

    await expectLater(
      applyRuntimeMemoryMutations(
        result,
        backend: backend,
        sessionKey: sessionKey,
        sourceMessageId: 'm-user-memory',
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('rust_runtime_removed:dbListMemoryPages'),
        ),
      ),
    );
    expect(backend.createProposalCalls, 0);
  });
}

final class _UnsupportedMemoryBackend extends TestAppBackend
    implements SecretaryBackend {
  int createProposalCalls = 0;

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
    createProposalCalls += 1;
    throw StateError('createSecretaryMemoryProposal must not be called');
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    throw UnsupportedError('rust_runtime_removed:dbListMemoryPages');
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
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
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
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

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
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
}
