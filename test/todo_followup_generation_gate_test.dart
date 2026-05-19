import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/todo_followup_generation_gate.dart';
import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/core/models/app_models.dart';

part 'todo_followup_generation_gate_test_support.dart';

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
          manualOverrideFollowup: false,
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
          manualOverrideFollowup: false,
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

  test(
      'preview loader reserves an auto slot via dedicated lookup when manual backlog stays saturated',
      () async {
    final store = _QueuedPreviewTodoFollowupGenerationStore(
      queuedDueResponses: <List<TodoFollowupGenerationJob>>[
        List<TodoFollowupGenerationJob>.generate(
          5,
          (index) => TodoFollowupGenerationJob(
            todoId: 'todo_manual_initial_$index',
            triggerKind: 'manual_regenerate',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: true,
            manualOverrideFollowup: false,
            taskTypeHint: 'research',
            createdAtMs: index,
            updatedAtMs: index,
          ),
          growable: false,
        ),
        List<TodoFollowupGenerationJob>.generate(
          10,
          (index) => TodoFollowupGenerationJob(
            todoId: 'todo_manual_expanded_$index',
            triggerKind: 'manual_regenerate',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: true,
            manualOverrideFollowup: false,
            taskTypeHint: 'research',
            createdAtMs: index,
            updatedAtMs: index,
          ),
          growable: false,
        ),
      ],
      dueAutoJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_auto_1',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 999,
          updatedAtMs: 999,
        ),
      ],
    );

    final jobs = await loadTodoFollowupGenerationPreviewJobs(
      store,
      nowMs: 123,
      batchLimit: 5,
    );

    expect(store.listDueJobsLimits, const <int>[5, 10, 20]);
    expect(store.listDueAutoJobsCallCount, 1);
    expect(jobs, hasLength(5));
    expect(
      jobs
          .where((job) => job.triggerKind == 'auto_create')
          .map((job) => job.todoId),
      const <String>['todo_auto_1'],
    );
    expect(
      jobs.where((job) => job.triggerKind == 'manual_regenerate').length,
      4,
    );
  });

  test(
      'Product intent: needs setup finalizer skips auto jobs and cancels manual jobs',
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
          manualOverrideFollowup: false,
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
          manualOverrideFollowup: false,
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

  test('manual retry defer cancels jobs after max attempts', () async {
    final store = _FakeTodoFollowupGenerationStore();

    final earliestRetryAtMs = await deferTodoFollowupGenerationJobsForRetry(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_auth',
          triggerKind: 'manual_regenerate',
          status: 'failed',
          attempts: 4,
          nextRetryAtMs: null,
          lastError: 'manual_followup_auth_unavailable',
          includeManualFollowups: true,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      nowMs: 1000,
      retryDelay: const Duration(seconds: 10),
      lastError: 'manual_followup_auth_unavailable',
      maxAttempts: 5,
    );

    expect(earliestRetryAtMs, isNull);
    expect(store.canceledTodoIds, const <String>['todo_manual_auth']);
    expect(store.skippedTodoIds, isEmpty);
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
          manualOverrideFollowup: false,
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

  testWidgets(
      'gate does not immediately reschedule itself from its own sync notification',
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
          manualOverrideFollowup: false,
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
    addTearDown(engine.stop);

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
    expect(backend.listDueJobsCallCount, 0);

    await tester.pump(const Duration(seconds: 3));
    expect(backend.listDueJobsCallCount, 1);

    await tester.pump(const Duration(milliseconds: 900));
    expect(backend.listDueJobsCallCount, 1);
  });

  testWidgets(
      'Product intent: missing AI route clears queued followup jobs even when legacy consent is disabled',
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
          manualOverrideFollowup: false,
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
          manualOverrideFollowup: false,
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

  testWidgets(
      'required AI gate still uses preview refetch expansion with legacy disabled consent',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': false,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: List<TodoFollowupGenerationJob>.generate(
        6,
        (index) => TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: index,
          updatedAtMs: index,
        ),
        growable: false,
      ),
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

    expect(backend.listDueJobsCallCount, 2);
    expect(backend.listDueJobsLimits, const <int>[5, 10]);
  });

  testWidgets('disposing gate mid-run does not finalize queued jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final dueJobsCompleter = Completer<List<TodoFollowupGenerationJob>>();
    final backend = _DelayedTodoFollowupGenerationGateBackend(
      dueJobsCompleter: dueJobsCompleter,
      fallbackDueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
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
    expect(backend.listDueJobsCallCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    dueJobsCompleter.complete(const <TodoFollowupGenerationJob>[
      TodoFollowupGenerationJob(
        todoId: 'todo_manual',
        triggerKind: 'manual_regenerate',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: true,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(backend.canceledTodoIds, isEmpty);
    expect(backend.skippedTodoIds, isEmpty);
    expect(backend.failedTodoIds, isEmpty);
    expect(backend.succeededTodoIds, isEmpty);
  });

  testWidgets(
      'external sync changes received mid-run trigger an immediate rerun',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _QueuedDueJobsTodoFollowupGenerationGateBackend(
      firstCallCompleter: Completer<List<TodoFollowupGenerationJob>>(),
      queuedResponses: <List<TodoFollowupGenerationJob>>[
        const <TodoFollowupGenerationJob>[
          TodoFollowupGenerationJob(
            todoId: 'todo_auto',
            triggerKind: 'auto_create',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: false,
            manualOverrideFollowup: false,
            taskTypeHint: 'research',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      ],
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    addTearDown(engine.stop);

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
    expect(backend.listDueJobsCallCount, 1);

    engine.notifyExternalChange();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(backend.listDueJobsCallCount, 1);

    backend.firstCallCompleter.complete(const <TodoFollowupGenerationJob>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.listDueJobsCallCount, 2);
    expect(backend.skippedTodoIds, contains('todo_auto'));
  });

  testWidgets('Product intent: manual pass is canceled when route needs setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
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

    expect(backend.canceledTodoIds, contains('todo_manual'));
    expect(backend.failedTodoIds, isEmpty);
  });

  testWidgets(
      'Product intent: needs-setup gate cancels manual regenerate while draining auto jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
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
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
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

    expect(backend.canceledTodoIds, contains('todo_manual'));
    expect(backend.skippedTodoIds, contains('todo_auto'));
    expect(backend.failedTodoIds, isEmpty);
  });

  testWidgets(
      'sync listeners are still notified when an earlier pass mutates before a later pass fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
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
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
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
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todosById: const <String, Todo>{
        'todo_manual': Todo(
          id: 'todo_manual',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        'todo_auto': Todo(
          id: 'todo_auto',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      cloudPromptOutcomes: const <Object>[
        '{"content":"Checked with current sources.","mode":"web_search","citations":[{"title":"Example","url":"https://example.com","domain":"example.com"}]}',
        _AiPromptFailure('boom'),
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
            child: SubscriptionScope(
              controller: _FixedSubscriptionStatusController(
                SubscriptionStatus.entitled,
              ),
              child: CloudAuthScope(
                controller: const _FixedCloudAuthController('token_1'),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://example.com',
                  modelName: 'cloud',
                ),
                child: SyncEngineScope(
                  engine: engine,
                  child: const TodoFollowupGenerationGate(
                    child: SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.generatedSuggestionTodoIds, contains('todo_manual'));
    expect(changeCount, 1);
  });

  testWidgets('mixed successful passes emit a single sync notification',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
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
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
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
          manualOverrideFollowup: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todosById: const <String, Todo>{
        'todo_manual': Todo(
          id: 'todo_manual',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        'todo_auto': Todo(
          id: 'todo_auto',
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
          providerType: 'openai-compatible',
          baseUrl: 'https://example.com',
          modelName: 'gpt-test',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      aiPromptCloudResponse:
          '{"content":"Checked with current sources.","mode":"web_search","citations":[{"title":"Example","url":"https://example.com","domain":"example.com"}]}',
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
            child: SubscriptionScope(
              controller: _FixedSubscriptionStatusController(
                SubscriptionStatus.entitled,
              ),
              child: CloudAuthScope(
                controller: const _FixedCloudAuthController('token_1'),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://example.com',
                  modelName: 'cloud',
                ),
                child: SyncEngineScope(
                  engine: engine,
                  child: const TodoFollowupGenerationGate(
                    child: SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.generatedSuggestionTodoIds, contains('todo_manual'));
    expect(backend.generatedSuggestionTodoIds, contains('todo_auto'));
    expect(changeCount, 1);
  });

  _registerRuntimeRoutePreferenceTests();
}
