import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/todo_followup_generation_gate.dart';
import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('mixed manual and auto jobs are split into separate generation passes',
      () {
    final plans = buildTodoFollowupGenerationPassPlans(
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        TodoFollowupGenerationJob(
          todoId: 'todo_auto',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    expect(plans, hasLength(2));
    expect(plans[0].hasManualRegenerateDueJob, isTrue);
    expect(
      plans[0].jobs.map((job) => job.todoId).toList(growable: false),
      const <String>['todo_manual'],
    );
    expect(plans[1].hasManualRegenerateDueJob, isFalse);
    expect(
      plans[1].jobs.map((job) => job.todoId).toList(growable: false),
      const <String>['todo_auto'],
    );
  });

  test('needs setup finalizer skips auto jobs and cancels manual jobs',
      () async {
    final store = _FakeTodoFollowupGenerationStore();

    await finalizeTodoFollowupGenerationJobsForNeedsSetup(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        TodoFollowupGenerationJob(
          todoId: 'todo_auto',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      nowMs: 123,
    );

    expect(store.canceledTodoIds, const <String>['todo_manual']);
    expect(store.skippedTodoIds, const <String>['todo_auto']);
  });

  testWidgets('needs-setup pass still notifies sync listeners for job updates',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_auto',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SyncEngineScope(
              engine: engine,
              child: const TodoFollowupGenerationGate(
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(changeCount, 0);

    await tester.pump(const Duration(seconds: 3));

    expect(backend.skippedTodoIds, contains('todo_auto'));
    expect(changeCount, greaterThan(0));
  });

  testWidgets('consent-disabled pass clears queued followup jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': false,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        TodoFollowupGenerationJob(
          todoId: 'todo_auto',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SyncEngineScope(
              engine: engine,
              child: const TodoFollowupGenerationGate(
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.canceledTodoIds, contains('todo_manual'));
    expect(backend.skippedTodoIds, contains('todo_auto'));
    expect(changeCount, greaterThan(0));
  });

  testWidgets('byok pass does not require a cloud token', (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_byok',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todosById: const <String, Todo>{
        'todo_byok': Todo(
          id: 'todo_byok',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      llmProfiles: const <LlmProfile>[
        LlmProfile(
          id: 'llm_1',
          name: 'BYOK',
          providerType: 'openai_compatible',
          baseUrl: 'https://example.com',
          modelName: 'gpt-test',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      aiPromptResponse:
          '{"content":"Not verified online. Summary collected from model knowledge.","mode":"model_knowledge","citations":[]}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const TodoFollowupGenerationGate(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.succeededTodoIds, contains('todo_byok'));
    expect(backend.generatedSuggestionTodoIds, contains('todo_byok'));
    expect(backend.failedTodoIds, isEmpty);
    expect(backend.canceledTodoIds, isEmpty);
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _FakeTodoFollowupGenerationGateBackend extends NativeAppBackend {
  _FakeTodoFollowupGenerationGateBackend({
    required this.dueJobs,
    this.todosById = const <String, Todo>{},
    this.llmProfiles = const <LlmProfile>[],
    this.aiPromptResponse,
  }) : super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<TodoFollowupGenerationJob> dueJobs;
  final Map<String, Todo> todosById;
  final List<LlmProfile> llmProfiles;
  final String? aiPromptResponse;
  final List<String> skippedTodoIds = <String>[];
  final List<String> canceledTodoIds = <String>[];
  final List<String> failedTodoIds = <String>[];
  final List<String> succeededTodoIds = <String>[];
  final List<String> generatedSuggestionTodoIds = <String>[];

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    return llmProfiles;
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async =>
      todosById[todoId];

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoFollowupSuggestion>[];

  @override
  Future<List<TodoFollowupSuggestion>> upsertGeneratedTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {
    generatedSuggestionTodoIds.add(todoId);
    return suggestions
        .map(
          (suggestion) => TodoFollowupSuggestion(
            id: 'generated_${generatedSuggestionTodoIds.length}',
            todoId: todoId,
            content: suggestion.content,
            state: 'pending',
            source: source,
            generationMode: suggestion.generationMode,
            generationKey: generationKey,
            citationsJson: suggestion.citationsJson,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    final response = aiPromptResponse;
    if (response == null) {
      throw StateError('aiPromptResponse not configured');
    }
    return response;
  }

  @override
  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    return dueJobs.take(limit).toList(growable: false);
  }

  @override
  Future<void> markTodoFollowupGenerationJobCanceled(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    canceledTodoIds.add(todoId);
  }

  @override
  Future<void> markTodoFollowupGenerationJobFailed(
    Uint8List key, {
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    failedTodoIds.add(todoId);
  }

  @override
  Future<void> markTodoFollowupGenerationJobRunning(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markTodoFollowupGenerationJobSkipped(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    skippedTodoIds.add(todoId);
  }

  @override
  Future<void> markTodoFollowupGenerationJobSucceeded(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    succeededTodoIds.add(todoId);
  }
}

final class _FakeTodoFollowupGenerationStore
    implements TodoFollowupGenerationStore {
  final List<String> canceledTodoIds = <String>[];
  final List<String> skippedTodoIds = <String>[];

  @override
  Future<Todo?> getTodo(String todoId) async => null;

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) async {}

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async =>
      const <TodoFollowupGenerationJob>[];

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) async =>
      const <TodoFollowupSuggestion>[];

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) async {
    canceledTodoIds.add(todoId);
  }

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) async {
    skippedTodoIds.add(todoId);
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {}
}
