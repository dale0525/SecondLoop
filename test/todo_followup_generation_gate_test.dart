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
      'Product intent: consent-disabled pass clears queued followup jobs',
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
      llmProfileOutcomes: const <Object>[
        <LlmProfile>[
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
        _AiPromptFailure('boom'),
      ],
      aiPromptResponse:
          '{"content":"Not verified online. Summary collected from model knowledge.","mode":"model_knowledge","citations":[]}',
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

    expect(backend.generatedSuggestionTodoIds, contains('todo_manual'));
    expect(backend.generatedSuggestionTodoIds, contains('todo_auto'));
    expect(changeCount, 1);
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

  testWidgets(
      'manual regenerate prefers cloud route even when BYOK is configured',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_cloud',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'live_info_lookup',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todosById: const <String, Todo>{
        'todo_manual_cloud': Todo(
          id: 'todo_manual_cloud',
          title: '去浦东机场接 MU5101',
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
      aiPromptCloudResponse:
          '{"content":"已查询到航站楼与预计到达时间。","mode":"web_search","citations":[{"title":"Airport","url":"https://airport.example/flight","domain":"airport.example"}]}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SubscriptionScope(
              controller: _FixedSubscriptionStatusController(
                SubscriptionStatus.unknown,
              ),
              child: const CloudAuthScope(
                controller: _FixedCloudAuthController('token_1'),
                gatewayConfig: CloudGatewayConfig(
                  baseUrl: 'https://example.com',
                  modelName: 'cloud',
                  supportsWebSearch: true,
                ),
                child: TodoFollowupGenerationGate(
                  child: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.cloudPromptCalls, 1);
    expect(backend.localPromptCalls, 0);
    expect(backend.succeededTodoIds, contains('todo_manual_cloud'));
  });

  testWidgets('gate runs for supported non-native backends via capability',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _CapabilityTodoFollowupGenerationGateBackend(
      dueJobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_capability',
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
    expect(backend.skippedTodoIds, contains('todo_capability'));
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
    this.aiPromptCloudResponse,
    List<Object> aiPromptOutcomes = const <Object>[],
    List<Object> llmProfileOutcomes = const <Object>[],
  })  : _aiPromptOutcomes = List<Object>.from(aiPromptOutcomes),
        _llmProfileOutcomes = List<Object>.from(llmProfileOutcomes),
        super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<TodoFollowupGenerationJob> dueJobs;
  final Map<String, Todo> todosById;
  final List<LlmProfile> llmProfiles;
  final String? aiPromptResponse;
  final String? aiPromptCloudResponse;
  final List<Object> _aiPromptOutcomes;
  final List<Object> _llmProfileOutcomes;
  final List<String> skippedTodoIds = <String>[];
  final List<String> canceledTodoIds = <String>[];
  final List<String> failedTodoIds = <String>[];
  final List<String> succeededTodoIds = <String>[];
  final List<String> generatedSuggestionTodoIds = <String>[];
  int listDueJobsCallCount = 0;
  int localPromptCalls = 0;
  int cloudPromptCalls = 0;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    if (_llmProfileOutcomes.isNotEmpty) {
      final outcome = _llmProfileOutcomes.removeAt(0);
      if (outcome is Exception) throw outcome;
      if (outcome is Error) throw outcome;
      return List<LlmProfile>.from(outcome as List<LlmProfile>);
    }

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
    localPromptCalls += 1;
    if (_aiPromptOutcomes.isNotEmpty) {
      final outcome = _aiPromptOutcomes.removeAt(0);
      if (outcome is Exception) throw outcome;
      if (outcome is Error) throw outcome;
      return '$outcome';
    }

    final response = aiPromptResponse;
    if (response == null) {
      throw StateError('aiPromptResponse not configured');
    }
    return response;
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    cloudPromptCalls += 1;
    final response = aiPromptCloudResponse;
    if (response == null) {
      throw StateError('aiPromptCloudResponse not configured');
    }
    return response;
  }

  @override
  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    listDueJobsCallCount += 1;
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

final class _FixedCloudAuthController implements CloudAuthController {
  const _FixedCloudAuthController(this._token);

  final String _token;

  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async => _token;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FixedSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FixedSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _AiPromptFailure implements Exception {
  const _AiPromptFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _CapabilityTodoFollowupGenerationGateBackend extends AppBackend {
  _CapabilityTodoFollowupGenerationGateBackend({required this.dueJobs});

  final List<TodoFollowupGenerationJob> dueJobs;
  final List<String> skippedTodoIds = <String>[];
  int listDueJobsCallCount = 0;

  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    listDueJobsCallCount += 1;
    return dueJobs.take(limit).toList(growable: false);
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async => null;

  @override
  Future<void> markTodoFollowupGenerationJobSkipped(
    Uint8List key, {
    required String todoId,
    required int nowMs,
  }) async {
    skippedTodoIds.add(todoId);
  }
}

final class _DelayedTodoFollowupGenerationGateBackend
    extends _FakeTodoFollowupGenerationGateBackend {
  _DelayedTodoFollowupGenerationGateBackend({
    required this.dueJobsCompleter,
    required List<TodoFollowupGenerationJob> fallbackDueJobs,
  }) : super(dueJobs: fallbackDueJobs);

  final Completer<List<TodoFollowupGenerationJob>> dueJobsCompleter;

  @override
  Future<List<TodoFollowupGenerationJob>> listDueTodoFollowupGenerationJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    listDueJobsCallCount += 1;
    return dueJobsCompleter.future;
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
