import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  setUp(BackendTaskPriorityAiService.clearSharedCacheForTest);

  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  test('parser accepts structured JSON rerank output', () {
    final parsed = parseTaskPriorityAiBatchResult(
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"do_now","confidence":"high"}]}',
    );

    expect(parsed.entries.single.todoId, 't1');
    expect(parsed.entries.single.priorityBand, TaskPriorityAiBand.focus);
    expect(parsed.entries.single.suggestedAction,
        TaskPrioritySuggestionKind.doNow);
  });

  test('parser keeps backward compatibility for legacy do token', () {
    final parsed = parseTaskPriorityAiBatchResult(
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"do","confidence":"high"}]}',
    );

    expect(parsed.entries.single.suggestedAction,
        TaskPrioritySuggestionKind.doNow);
  });

  test('high confidence focus recommendation upgrades snapshot', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[todo(id: 't1', title: 'Clarify scope', updatedAtMs: 10)],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 20,
            reason: 'It blocks the rest of the project.',
            suggestedAction: TaskPrioritySuggestionKind.clarify,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 't1');
    expect(snapshot.primaryFocus?.reasonText,
        'It blocks the rest of the project.');
    expect(snapshot.primaryFocus?.suggestedAction,
        TaskPrioritySuggestionKind.clarify);
  });

  test('service falls back cleanly when AI call fails', () async {
    final service = BackendTaskPriorityAiService.forTesting(
      backend: _ThrowingAskBackend(),
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: '',
      idToken: '',
      modelName: 'gpt-4o-mini',
    );

    await expectLater(
      service.rerank(
        TaskPriorityAiRequest(
          nowLocal: DateTime(2026, 3, 13, 10, 0),
          candidates: const <TaskPriorityAiCandidate>[
            TaskPriorityAiCandidate(
              todoId: 't1',
              title: 'Fix bug',
              status: 'open',
              band: TaskPriorityBand.decide,
              dueState: 'unscheduled',
              ruleScore: 10,
              updatedAtMs: 0,
              recentInteractionSummary: '',
              sourceSummary: '',
              isRepeatedlyDeferred: false,
              isPotentialBlocker: false,
              isQuickWin: false,
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('service uses non-persistent rerank API', () async {
    final backend = _DirectTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: '',
      idToken: '',
      modelName: 'gpt-4o-mini',
    );

    final result = await service.rerank(
      TaskPriorityAiRequest(
        nowLocal: DateTime(2026, 3, 13, 10, 0),
        candidates: const <TaskPriorityAiCandidate>[
          TaskPriorityAiCandidate(
            todoId: 't1',
            title: 'Fix bug',
            status: 'open',
            band: TaskPriorityBand.decide,
            dueState: 'unscheduled',
            ruleScore: 10,
            updatedAtMs: 0,
            recentInteractionSummary: '',
            sourceSummary: '',
            isRepeatedlyDeferred: false,
            isPotentialBlocker: true,
            isQuickWin: false,
          ),
        ],
      ),
    );

    expect(result.entries.single.todoId, 't1');
    final messages = await backend.listMessages(Uint8List(32), 'loop_home');
    expect(messages, isEmpty);
  });

  test('service uses dedicated cloud gateway rerank API', () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
    );

    final result = await service.rerank(
      TaskPriorityAiRequest(
        nowLocal: DateTime(2026, 3, 13, 10, 0),
        candidates: const <TaskPriorityAiCandidate>[
          TaskPriorityAiCandidate(
            todoId: 't1',
            title: 'Fix bug',
            status: 'open',
            band: TaskPriorityBand.decide,
            dueState: 'unscheduled',
            ruleScore: 10,
            updatedAtMs: 0,
            recentInteractionSummary: '',
            sourceSummary: '',
            isRepeatedlyDeferred: false,
            isPotentialBlocker: true,
            isQuickWin: false,
          ),
        ],
      ),
    );

    expect(result.entries.single.todoId, 't1');
    expect(backend.taskPriorityCalls, 0);
    expect(backend.cloudTaskPriorityCalls, 1);
  });

  test('service includes current app locale in prompt', () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: '',
      idToken: '',
      modelName: 'gpt-locale-test',
      localeTag: 'zh-CN',
    );

    await service.rerank(
      TaskPriorityAiRequest(
        nowLocal: DateTime(2026, 3, 13, 10, 0),
        candidates: const <TaskPriorityAiCandidate>[
          TaskPriorityAiCandidate(
            todoId: 't1',
            title: 'Fix bug',
            status: 'open',
            band: TaskPriorityBand.decide,
            dueState: 'unscheduled',
            ruleScore: 10,
            updatedAtMs: 0,
            recentInteractionSummary: '',
            sourceSummary: '',
            isRepeatedlyDeferred: false,
            isPotentialBlocker: true,
            isQuickWin: false,
          ),
        ],
      ),
    );

    expect(backend.prompts.single, contains('current app language (zh-CN)'));
  });

  test('service deduplicates cross-instance reranks with only clock drift',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    final requestA = TaskPriorityAiRequest(
      nowLocal: DateTime(2026, 3, 13, 10, 0),
      candidates: const <TaskPriorityAiCandidate>[
        TaskPriorityAiCandidate(
          todoId: 't1',
          title: 'Fix bug',
          status: 'open',
          band: TaskPriorityBand.decide,
          dueState: 'unscheduled',
          ruleScore: 10,
          updatedAtMs: 0,
          recentInteractionSummary: '',
          sourceSummary: '',
          isRepeatedlyDeferred: false,
          isPotentialBlocker: true,
          isQuickWin: false,
        ),
      ],
    );
    final requestB = TaskPriorityAiRequest(
      nowLocal: DateTime(2026, 3, 13, 10, 0, 6),
      candidates: requestA.candidates,
    );

    final serviceA = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: '',
      idToken: '',
      modelName: 'gpt-dedupe-test',
      localeTag: 'zh-CN',
    );
    final serviceB = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: '',
      idToken: '',
      modelName: 'gpt-dedupe-test',
      localeTag: 'zh-CN',
    );

    await serviceA.rerank(requestA);
    await serviceB.rerank(requestB);

    expect(backend.taskPriorityCalls, 1);
  });
}

final class _ThrowingAskBackend extends TestAppBackend {
  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    throw StateError('boom');
  }
}

final class _DirectTaskPriorityBackend extends TestAppBackend {
  static const String _response =
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"do_now","confidence":"high"}]}';

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    return _response;
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    throw StateError('askAiStream should not be used for task priority rerank');
  }
}

final class _RecordingTaskPriorityBackend extends TestAppBackend {
  static const String _response =
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"今天优先处理。","suggested_action":"do_now","confidence":"high"}]}';

  final List<String> prompts = <String>[];
  int taskPriorityCalls = 0;
  int cloudTaskPriorityCalls = 0;

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    prompts.add(prompt);
    taskPriorityCalls += 1;
    return _response;
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    prompts.add(prompt);
    cloudTaskPriorityCalls += 1;
    return _response;
  }
}
