import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
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
    int? reviewStage,
    int? nextReviewAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: null,
    );
  }

  test('initial review queue tasks are not marked repeatedly deferred', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 't1',
          title: '预约师傅修电视机',
          updatedAtMs: 10,
          reviewStage: 0,
          nextReviewAtMs: nowLocal
              .add(const Duration(days: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: nowLocal,
    );

    final request = buildTaskPriorityAiRequest(snapshot, nowLocal: nowLocal);

    expect(request.candidates, hasLength(1));
    expect(request.candidates.single.isRepeatedlyDeferred, isFalse);
  });

  test('high review stages still surface repeated deferral signal', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 't1',
          title: 'Eventually decide this',
          updatedAtMs: 10,
          reviewStage: 2,
          nextReviewAtMs: nowLocal
              .add(const Duration(days: 7))
              .toUtc()
              .millisecondsSinceEpoch,
        ),
      ],
      nowLocal: nowLocal,
    );

    final request = buildTaskPriorityAiRequest(snapshot, nowLocal: nowLocal);

    expect(request.candidates, hasLength(1));
    expect(request.candidates.single.isRepeatedlyDeferred, isTrue);
  });

  test('parser accepts structured JSON rerank output', () {
    final parsed = parseTaskPriorityAiBatchResult(
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"do_now","confidence":"high"}]}',
    );

    expect(parsed.entries.single.todoId, 't1');
    expect(parsed.entries.single.legacyRanking?.priorityBand,
        TaskPriorityAiBand.focus);
    expect(parsed.entries.single.legacyRanking?.suggestedAction,
        TaskPrioritySuggestionKind.doNow);
  });

  test('parser keeps backward compatibility for legacy do token', () {
    final parsed = parseTaskPriorityAiBatchResult(
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"do","confidence":"high"}]}',
    );

    expect(parsed.entries.single.legacyRanking?.suggestedAction,
        TaskPrioritySuggestionKind.doNow);
  });

  test('ai entry can omit legacy ranking fields in serialized output', () {
    const entry = TaskPriorityAiEntry(
      todoId: 't1',
      semanticAdjustment: 14,
      reason: 'Important and urgent.',
      confidence: TaskPriorityAiConfidence.high,
      isImportant: true,
      isUrgent: true,
    );

    expect(entry.toJson().containsKey('priority_band'), isFalse);
    expect(entry.toJson().containsKey('suggested_action'), isFalse);
  });

  test('parser keeps backward compatibility for legacy ranking fields', () {
    final parsed = parseTaskPriorityAiBatchResult(
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"It unblocks work.","suggested_action":"clarify","confidence":"high","is_important":true,"is_urgent":false}]}',
    );

    expect(parsed.entries.single.legacyRanking?.priorityBand,
        TaskPriorityAiBand.focus);
    expect(parsed.entries.single.legacyRanking?.suggestedAction,
        TaskPrioritySuggestionKind.clarify);
    expect(parsed.entries.single.isImportant, isTrue);
    expect(parsed.entries.single.isUrgent, isFalse);
  });

  test('high confidence ai assessment keeps rule-derived action', () {
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[todo(id: 't1', title: 'Clarify scope', updatedAtMs: 10)],
      nowLocal: nowLocal,
      aiResult: const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 't1',
            semanticAdjustment: 20,
            reason: 'It blocks the rest of the project.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );

    expect(snapshot.primaryFocus?.todo.id, 't1');
    expect(snapshot.primaryFocus?.reasonText,
        'It blocks the rest of the project.');
    expect(snapshot.primaryFocus?.suggestedAction,
        TaskPrioritySuggestionKind.schedule);
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
              ruleIsImportant: false,
              ruleIsUrgent: false,
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
            ruleIsImportant: false,
            ruleIsUrgent: false,
          ),
        ],
      ),
    );

    expect(result.entries.single.todoId, 't1');
    final messages = await backend.listMessages(Uint8List(32), 'loop_home');
    expect(messages, isEmpty);
  });

  test('store writes shared assessments after fresh rerank', () async {
    SharedPreferences.setMockInitialValues({});
    final writtenPayloads = <Map<String, TaskPriorityAiCachedAssessment>>[];
    final writtenActiveIds = <List<String>>[];
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        const Todo(
          id: 'focus',
          title: 'Fresh task',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 10,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
      resolveAiService: () async => _SuccessfulRerankAiService(),
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        writtenPayloads
            .add(Map<String, TaskPriorityAiCachedAssessment>.from(entries));
        writtenActiveIds.add(activeTodoIds.toList(growable: false));
      },
    );

    await store.refresh();

    expect(writtenPayloads, hasLength(1));
    expect(
        writtenPayloads.single['focus']?.entry.reason, 'Fresh rerank result.');
    expect(writtenActiveIds.single, <String>['focus']);
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
            ruleIsImportant: false,
            ruleIsUrgent: false,
          ),
        ],
      ),
    );

    expect(result.entries.single.todoId, 't1');
    expect(backend.taskPriorityCalls, 0);
    expect(backend.cloudTaskPriorityCalls, 1);
  });

  test('shared assessments ignore expired remote entries', () async {
    final backend = _RecordingTaskPriorityBackend();
    backend.sharedAssessmentsResponse = jsonEncode(<String, Object?>{
      'ok': true,
      'scope': 'cloud-scope',
      'entries': <Object?>[
        <String, Object?>{
          'todo_id': 'focus',
          'semantic_adjustment': 18,
          'reason': 'Expired shared result.',
          'confidence': 'high',
          'request_signature': 'sig',
          'computed_at_ms': DateTime(2026, 3, 13, 9, 0).millisecondsSinceEpoch,
        },
      ],
    });
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );

    final entries = await service.readSharedAssessments(
      nowLocal: DateTime(2026, 3, 13, 10, 0),
    );

    expect(entries, isEmpty);
  });

  test('byok service skips shared assessment network even with token and scope',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    backend.sharedAssessmentsResponse = jsonEncode(<String, Object?>{
      'ok': true,
      'scope': 'byok-scope',
      'entries': <Object?>[
        <String, Object?>{
          'todo_id': 'focus',
          'semantic_adjustment': 18,
          'reason': 'Cloud result must not leak into BYOK.',
          'confidence': 'high',
          'request_signature': 'sig-focus',
          'computed_at_ms': DateTime(2026, 3, 13, 10, 0).millisecondsSinceEpoch,
        },
      ],
    });
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'stale-cloud-token',
      modelName: 'gpt-byok-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'byok-scope',
    );

    final entries = await service.readSharedAssessments(
      nowLocal: DateTime(2026, 3, 13, 10, 5),
    );
    await service.writeSharedAssessments(
      entries: const <String, TaskPriorityAiCachedAssessment>{},
      activeTodoIds: const <String>[],
    );

    expect(entries, isEmpty);
    expect(backend.sharedAssessmentFetchCalls, 0);
    expect(backend.sharedAssessmentUpsertCalls, 0);
    expect(backend.lastSharedAssessmentsPayload, isNull);
  });

  test('shared assessment writes declare full snapshot replacement', () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );

    await service.writeSharedAssessments(
      entries: <String, TaskPriorityAiCachedAssessment>{
        'focus': TaskPriorityAiCachedAssessment(
          entry: const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Fresh shared result.',
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

    expect(backend.lastSharedAssessmentsPayload, isNotNull);
    expect(
      backend.lastSharedAssessmentsPayload!['replace_missing_entries'],
      isTrue,
    );
    expect(backend.lastSharedAssessmentsPayload!['scope'], 'cloud-scope');
    expect(
      backend.lastSharedAssessmentsPayload!['updated_at_ms'],
      DateTime(2026, 3, 13, 10, 0).millisecondsSinceEpoch,
    );
  });

  test(
      'shared assessment writes use freshest computed time for non-empty snapshots',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );

    await service.writeSharedAssessments(
      entries: <String, TaskPriorityAiCachedAssessment>{
        'focus': TaskPriorityAiCachedAssessment(
          entry: const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Earlier shared result.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: false,
          ),
          requestSignature: 'sig-focus',
          computedAtLocal: DateTime(2026, 3, 13, 10, 0),
        ),
        'backlog': TaskPriorityAiCachedAssessment(
          entry: const TaskPriorityAiEntry(
            todoId: 'backlog',
            semanticAdjustment: 12,
            reason: 'Latest shared result.',
            confidence: TaskPriorityAiConfidence.medium,
            isImportant: false,
            isUrgent: false,
          ),
          requestSignature: 'sig-backlog',
          computedAtLocal: DateTime(2026, 3, 13, 10, 5),
        ),
      },
      activeTodoIds: const <String>['focus', 'backlog'],
    );

    expect(backend.lastSharedAssessmentsPayload, isNotNull);
    expect(
      backend.lastSharedAssessmentsPayload!['updated_at_ms'],
      DateTime(2026, 3, 13, 10, 5).millisecondsSinceEpoch,
    );
  });

  test('empty shared assessment snapshot still declares full replacement',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );

    await service.writeSharedAssessments(
      entries: const <String, TaskPriorityAiCachedAssessment>{},
      activeTodoIds: const <String>[],
    );

    expect(backend.lastSharedAssessmentsPayload, isNotNull);
    expect(
      backend.lastSharedAssessmentsPayload!['replace_missing_entries'],
      isTrue,
    );
    expect(
      backend.lastSharedAssessmentsPayload!['entries'],
      isEmpty,
    );
    expect(
      backend.lastSharedAssessmentsPayload!['updated_at_ms'],
      isA<int>(),
    );
  });

  test(
      'shared assessment writes avoid full replacement for partial active snapshots',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );

    await service.writeSharedAssessments(
      entries: <String, TaskPriorityAiCachedAssessment>{
        'focus': TaskPriorityAiCachedAssessment(
          entry: const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Fresh shared result.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: false,
          ),
          requestSignature: 'sig-focus',
          computedAtLocal: DateTime(2026, 3, 13, 10, 0),
        ),
      },
      activeTodoIds: const <String>['focus', 'backlog'],
    );

    expect(backend.lastSharedAssessmentsPayload, isNotNull);
    expect(
      backend.lastSharedAssessmentsPayload!['replace_missing_entries'],
      isFalse,
    );
    expect(backend.lastSharedAssessmentsPayload!['scope'], 'cloud-scope');
  });

  test(
      'store keeps shared assessment writes partial when active todos exceed candidate limit',
      () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RecordingTaskPriorityBackend(echoCandidates: true);
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-cloud-test',
      localeTag: 'en-US',
      cacheScopeKeyOverride: 'cloud-scope',
    );
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        for (var i = 0; i < 33; i += 1)
          todo(
            id: 'todo-$i',
            title: 'Task $i',
            updatedAtMs: 1000 - i,
          ),
      ],
      resolveAiService: () async => service,
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async =>
          const <String, TaskPriorityAiCachedAssessment>{},
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        await (aiService as BackendTaskPriorityAiService)
            .writeSharedAssessments(
          entries: entries,
          activeTodoIds: activeTodoIds,
        );
      },
    );

    await store.refresh();

    expect(backend.lastSharedAssessmentsPayload, isNotNull);
    expect(backend.cloudTaskPriorityCalls, 1);
    expect(
      backend.lastSharedAssessmentsPayload!['replace_missing_entries'],
      isFalse,
    );
    expect(
      (backend.lastSharedAssessmentsPayload!['entries'] as List).length,
      32,
    );
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
            ruleIsImportant: false,
            ruleIsUrgent: false,
          ),
        ],
      ),
    );

    expect(backend.prompts.single, contains('current app language (zh-CN)'));
  });

  test('cacheScopeKey omits empty partition key entries', () {
    final decoded = jsonDecode(
      buildTaskPriorityAiCacheScopeKey(
        route: AskAiRouteKind.byok,
        gatewayBaseUrl: 'https://gateway.example',
        modelName: 'gpt-4o-mini',
        localeTag: 'zh-CN',
      ),
    ) as List<dynamic>;

    expect(decoded, <String>[
      'byok',
      'https://gateway.example',
      'gpt-4o-mini',
      'zh-CN',
    ]);
  });

  test('cacheScopeKey stays unique when config values contain pipes', () {
    final backend = _RecordingTaskPriorityBackend();
    final serviceA = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://gateway.example/a|b',
      idToken: '',
      modelName: 'c',
      localeTag: 'zh-CN',
    );
    final serviceB = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://gateway.example/a',
      idToken: '',
      modelName: 'b|c',
      localeTag: 'zh-CN',
    );

    expect(serviceA.cacheScopeKey, isNot(serviceB.cacheScopeKey));
  });

  test('cloud gateway cacheScopeKey stays empty without resolved user scope',
      () {
    final backend = _RecordingTaskPriorityBackend();
    final service = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token-a',
      modelName: 'gpt-cloud',
      localeTag: 'zh-CN',
    );

    expect(service.cacheScopeKey, isEmpty);
  });

  test('cloud gateway rerank cache does not collide across id tokens',
      () async {
    final backend = _RecordingTaskPriorityBackend();
    final request = TaskPriorityAiRequest(
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
          ruleIsImportant: false,
          ruleIsUrgent: false,
        ),
      ],
    );

    final serviceA = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token-a',
      modelName: 'gpt-cloud',
      localeTag: 'zh-CN',
    );
    final serviceB = BackendTaskPriorityAiService.forTesting(
      backend: backend,
      sessionKey: Uint8List(32),
      route: AskAiRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token-b',
      modelName: 'gpt-cloud',
      localeTag: 'zh-CN',
    );

    await serviceA.rerank(request);
    await serviceB.rerank(request);

    expect(backend.cloudTaskPriorityCalls, 2);
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
          ruleIsImportant: false,
          ruleIsUrgent: false,
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

final class _SuccessfulRerankAiService extends TaskPriorityAiService {
  @override
  String get cacheScopeKey => 'shared-write-cache';

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    return const TaskPriorityAiBatchResult(
      entries: <TaskPriorityAiEntry>[
        TaskPriorityAiEntry(
          todoId: 'focus',
          semanticAdjustment: 22,
          reason: 'Fresh rerank result.',
          confidence: TaskPriorityAiConfidence.high,
          isImportant: true,
          isUrgent: true,
        ),
      ],
    );
  }
}

final class _RecordingTaskPriorityBackend extends TestAppBackend {
  static const String _response =
      '{"entries":[{"todo_id":"t1","priority_band":"focus","semantic_adjustment":14,"reason":"今天优先处理。","suggested_action":"do_now","confidence":"high"}]}';

  _RecordingTaskPriorityBackend({this.echoCandidates = false});

  final bool echoCandidates;

  final List<String> prompts = <String>[];
  String sharedAssessmentsResponse =
      '{"ok":true,"scope":"cloud-scope","entries":[]}';
  Map<String, Object?>? lastSharedAssessmentsPayload;
  int taskPriorityCalls = 0;
  int cloudTaskPriorityCalls = 0;
  int sharedAssessmentFetchCalls = 0;
  int sharedAssessmentUpsertCalls = 0;

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
    if (echoCandidates) {
      const marker = 'Payload:\n';
      final markerIndex = prompt.lastIndexOf(marker);
      if (markerIndex >= 0) {
        final payloadJson = prompt.substring(markerIndex + marker.length);
        final payload = jsonDecode(payloadJson) as Map;
        final candidates =
            (payload['candidates'] as List?) ?? const <Object?>[];
        return jsonEncode(<String, Object?>{
          'entries': candidates.map((candidate) {
            final candidateJson = (candidate as Map)
                .map((key, value) => MapEntry(key.toString(), value));
            return <String, Object?>{
              'todo_id': candidateJson['todo_id'],
              'semantic_adjustment': 14,
              'reason': 'Echoed candidate result.',
              'confidence': 'high',
              'is_important': false,
              'is_urgent': false,
            };
          }).toList(growable: false),
        });
      }
    }
    return _response;
  }

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    sharedAssessmentFetchCalls += 1;
    return sharedAssessmentsResponse;
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    sharedAssessmentUpsertCalls += 1;
    final decoded = jsonDecode(payloadJson) as Map;
    lastSharedAssessmentsPayload =
        decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
