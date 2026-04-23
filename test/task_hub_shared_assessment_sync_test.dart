import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';

import 'test_backend.dart';

void main() {
  test('shared assessments client reads remote cache without rerank service',
      () async {
    final backend = _RecordingSharedAssessmentBackend(
      fetchResponseJson: jsonEncode(<String, Object?>{
        'ok': true,
        'scope': 'cloud-scope',
        'entries': <Object?>[
          <String, Object?>{
            'todo_id': 'focus',
            'semantic_adjustment': 18,
            'reason': 'Shared cloud reason.',
            'confidence': 'high',
            'is_important': true,
            'is_urgent': false,
            'request_signature': 'sig-focus',
            'computed_at_ms':
                DateTime(2026, 3, 13, 10, 0).millisecondsSinceEpoch,
          },
        ],
      }),
    );
    final client = BackendTaskPriorityAiSharedAssessmentsClient(
      backend: backend,
      sessionKey: Uint8List(32),
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'test-id-token',
      modelName: 'cloud-model',
      localeTag: 'en',
      cacheScopeKey: 'cloud-scope',
    );

    final entries = await client.read(
      nowLocal: DateTime(2026, 3, 13, 10, 5),
    );

    expect(entries['focus']?.entry.reason, 'Shared cloud reason.');
    expect(backend.fetchCalls, 1);
  });

  test('shared assessments client writes remote cache without rerank service',
      () async {
    final backend = _RecordingSharedAssessmentBackend(fetchResponseJson: '{}');
    final client = BackendTaskPriorityAiSharedAssessmentsClient(
      backend: backend,
      sessionKey: Uint8List(32),
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'test-id-token',
      modelName: 'cloud-model',
      localeTag: 'en',
      cacheScopeKey: 'cloud-scope',
    );

    await client.write(
      entries: <String, TaskPriorityAiCachedAssessment>{
        'focus': TaskPriorityAiCachedAssessment(
          entry: const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Shared cloud reason.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: false,
          ),
          requestSignature: 'sig-focus',
          computedAtLocal: DateTime(2026, 3, 13, 10, 0),
        ),
      },
      activeTodoIds: const <String>['focus'],
    );

    expect(backend.upsertCalls, 1);
    expect(backend.lastPayload?['scope'], 'cloud-scope');
    expect(backend.lastPayload?['replace_missing_entries'], isTrue);
  });
}

final class _RecordingSharedAssessmentBackend extends TestAppBackend {
  _RecordingSharedAssessmentBackend({required this.fetchResponseJson});

  final String fetchResponseJson;
  int fetchCalls = 0;
  int upsertCalls = 0;
  Map<String, Object?>? lastPayload;

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    fetchCalls += 1;
    return fetchResponseJson;
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
    final decoded = jsonDecode(payloadJson) as Map;
    lastPayload = decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
