import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('store resolves shared assessments client once per refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RecordingSharedAssessmentBackend();
    var resolveCalls = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => _ImmediateAiService(
        cacheScopeKey: 'cloud-scope',
      ),
      resolveSharedAiAssessmentsClient: ({required cacheScopeKey}) async {
        resolveCalls += 1;
        expect(cacheScopeKey, 'cloud-scope');
        return BackendTaskPriorityAiSharedAssessmentsClient(
          backend: backend,
          sessionKey: Uint8List(32),
          gatewayBaseUrl: 'https://gateway.test',
          idToken: 'test-id-token',
          modelName: 'cloud-model',
          localeTag: 'en',
          cacheScopeKey: cacheScopeKey,
        );
      },
    );

    await store.refresh();

    expect(resolveCalls, 1);
    expect(backend.fetchCalls, 1);
    expect(backend.upsertCalls, 1);
  });

  test('store forwards configured TTL to shared assessments client', () async {
    SharedPreferences.setMockInitialValues({});
    const cacheTtl = Duration(seconds: 7);
    final client = _CapturingSharedAssessmentsClient();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => _ImmediateAiService(
        cacheScopeKey: 'cloud-scope',
      ),
      resolveSharedAiAssessmentsClient: ({required cacheScopeKey}) async {
        expect(cacheScopeKey, 'cloud-scope');
        return client;
      },
      aiCacheTtl: cacheTtl,
    );

    await store.refresh();

    expect(client.readCacheTtl, cacheTtl);
  });
}

Todo todo({
  required String id,
  required String title,
  required int updatedAtMs,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: null,
    status: 'open',
    sourceEntryId: null,
    createdAtMs: 0,
    updatedAtMs: updatedAtMs,
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
  );
}

final class _ImmediateAiService extends TaskPriorityAiService {
  _ImmediateAiService({required this.cacheScopeKey});

  @override
  final String cacheScopeKey;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
    TaskPriorityAiRequest request,
  ) async {
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: 24,
              reason: 'Fresh shared-client result.',
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _CapturingSharedAssessmentsClient
    extends BackendTaskPriorityAiSharedAssessmentsClient {
  _CapturingSharedAssessmentsClient()
      : super(
          backend: _RecordingSharedAssessmentBackend(),
          sessionKey: Uint8List(32),
          gatewayBaseUrl: 'https://gateway.test',
          idToken: 'test-id-token',
          modelName: 'cloud-model',
          localeTag: 'en',
          cacheScopeKey: 'cloud-scope',
        );

  Duration? readCacheTtl;

  @override
  Future<Map<String, TaskPriorityAiCachedAssessment>> read({
    required DateTime nowLocal,
    Duration cacheTtl = defaultTaskPriorityAiCacheTtl,
  }) async {
    readCacheTtl = cacheTtl;
    return const <String, TaskPriorityAiCachedAssessment>{};
  }

  @override
  Future<void> write({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) async {}
}

final class _RecordingSharedAssessmentBackend extends TestAppBackend {
  int fetchCalls = 0;
  int upsertCalls = 0;

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    fetchCalls += 1;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'scope': cacheScopeKey,
      'entries': <Object?>[],
    });
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    upsertCalls += 1;
  }
}
