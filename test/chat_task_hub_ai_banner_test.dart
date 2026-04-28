import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';
import 'task_priority_test_helpers.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void main() {
  setUp(() {
    BackendTaskPriorityAiService.clearSharedCacheForTest();
  });

  testWidgets('Chat task hub banner shows shared ai source label',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    const todo = Todo(
      id: 'todo:shared-label',
      title: 'Shared chat task',
      dueAtMs: null,
      status: 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
    final requestSignature =
        stableTaskPriorityRequestSignatureFor(todo, nowLocal);

    final backend = _AgendaBackend(
      todos: const [todo],
      sharedTaskPriorityAssessmentsJson: jsonEncode(<String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            ...const TaskPriorityAiEntry(
              todoId: 'todo:shared-label',
              semanticAdjustment: 18,
              reason: 'Shared AI result.',
              confidence: TaskPriorityAiConfidence.high,
            ).toJson(),
            'request_signature': requestSignature,
            'computed_at_ms': nowLocal.millisecondsSinceEpoch,
          },
        ],
      }),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: const _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://cloud.secondloop.test',
            modelName: 'cloud',
          ),
          child: SubscriptionScope(
            controller: _FakeSubscriptionController(
              SubscriptionStatus.entitled,
            ),
            child: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const MaterialApp(
                  home: ChatPage(
                    conversation: Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
      findsOneWidget,
    );
    expect(find.text('Shared AI insight'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(find.byTooltip('AI recommends this now'), findsOneWidget);
    expect(find.text('Shared AI result.'), findsWidgets);
  });

  testWidgets('Chat task hub banner shows cached ai source label',
      (tester) async {
    final nowLocal = DateTime.now();
    final cacheScopeKey = buildTaskPriorityAiCacheScopeKey(
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://api.openai.com/v1',
      modelName: 'gpt-4o-mini',
      localeTag: 'en',
      partitionKey: '["p1","openai-compatible"]',
    );
    final fallbackCacheScopeKey = buildTaskPriorityAiCacheScopeKey(
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://api.openai.com/v1',
      modelName: 'gpt-4o-mini',
      localeTag: 'en-US',
      partitionKey: '["p1","openai-compatible"]',
    );
    const todo = Todo(
      id: 'todo:cached-label',
      title: 'Cached chat task',
      dueAtMs: null,
      status: 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
    final requestSignature =
        stableTaskPriorityRequestSignatureFor(todo, nowLocal);
    SharedPreferences.setMockInitialValues({
      'task_priority_ai_cache_v3': jsonEncode(<String, Object?>{
        'scopes': <String, Object?>{
          for (final key in <String>[cacheScopeKey, fallbackCacheScopeKey])
            key: <String, Object?>{
              'entries': <String, Object?>{
                'todo:cached-label': TaskPriorityAiCachedAssessment(
                  entry: const TaskPriorityAiEntry(
                    todoId: 'todo:cached-label',
                    semanticAdjustment: 14,
                    reason: 'Cached AI result.',
                    confidence: TaskPriorityAiConfidence.high,
                  ),
                  requestSignature: requestSignature,
                  computedAtLocal: nowLocal,
                ).toJson(),
              },
            },
        },
      }),
    });

    final backend = _AgendaBackend(
      todos: const [todo],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
      findsOneWidget,
    );
    expect(find.text('Cached AI insight'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(find.byTooltip('AI recommends this now'), findsOneWidget);
    expect(find.text('Cached AI result.'), findsWidgets);
  });

  testWidgets('Chat task hub banner reuses cached ai result in compact mode',
      (tester) async {
    final nowLocal = DateTime.now();
    final cacheScopeKey = buildTaskPriorityAiCacheScopeKey(
      route: AskAiRouteKind.byok,
      gatewayBaseUrl: 'https://api.openai.com/v1',
      modelName: 'gpt-4o-mini',
      localeTag: 'en',
      partitionKey: '["p1","openai-compatible"]',
    );
    const todo = Todo(
      id: 'todo:bootstrap-label',
      title: 'Bootstrap cached task',
      dueAtMs: null,
      status: 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
    final requestSignature =
        stableTaskPriorityRequestSignatureFor(todo, nowLocal);
    SharedPreferences.setMockInitialValues({
      'task_priority_ai_cache_v3': jsonEncode(<String, Object?>{
        'scopes': <String, Object?>{
          cacheScopeKey: <String, Object?>{
            'entries': <String, Object?>{
              'todo:bootstrap-label': TaskPriorityAiCachedAssessment(
                entry: const TaskPriorityAiEntry(
                  todoId: 'todo:bootstrap-label',
                  semanticAdjustment: 14,
                  reason: 'Bootstrap cached AI result.',
                  confidence: TaskPriorityAiConfidence.high,
                ),
                requestSignature: requestSignature,
                computedAtLocal: nowLocal,
              ).toJson(),
            },
          },
        },
      }),
    });

    final backend = _AgendaBackend(
      todos: const [todo],
      llmProfiles: const <LlmProfile>[],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
      findsOneWidget,
    );
    expect(find.text('Cached AI insight'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(find.byTooltip('AI recommends this now'), findsOneWidget);
    expect(find.text('Bootstrap cached AI result.'), findsWidgets);
  });

  testWidgets('Chat task hub banner shows live ai source label',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: const [
        Todo(
          id: 'todo:ai-label',
          title: 'AI-ranked chat task',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
      taskPriorityAiResponseJson: jsonEncode(
        const TaskPriorityAiBatchResult(
          entries: <TaskPriorityAiEntry>[
            TaskPriorityAiEntry(
              todoId: 'todo:ai-label',
              semanticAdjustment: 18,
              reason: 'Live AI result.',
              confidence: TaskPriorityAiConfidence.high,
            ),
          ],
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
      findsOneWidget,
    );
    expect(find.text('Live AI insight'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_banner_focus_indicator')),
        findsOneWidget);
    expect(find.byTooltip('AI recommends this now'), findsOneWidget);
    expect(find.text('Live AI result.'), findsWidgets);
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController();

  @override
  String? get uid => 'cloud-user-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'cloud-token';

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

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _AgendaBackend extends TestAppBackend {
  _AgendaBackend({
    required List<Todo> todos,
    this.taskPriorityAiResponseJson,
    this.sharedTaskPriorityAssessmentsJson,
    List<LlmProfile>? llmProfiles,
  })  : _todosById = <String, Todo>{
          for (final todo in todos) todo.id: todo,
        },
        _llmProfiles = List<LlmProfile>.from(llmProfiles ??
            const <LlmProfile>[
              LlmProfile(
                id: 'p1',
                name: 'OpenAI',
                providerType: 'openai-compatible',
                baseUrl: 'https://api.openai.com/v1',
                modelName: 'gpt-4o-mini',
                isActive: true,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
            ]);

  final Map<String, Todo> _todosById;
  final List<LlmProfile> _llmProfiles;
  final String? taskPriorityAiResponseJson;
  final String? sharedTaskPriorityAssessmentsJson;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_llmProfiles);

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      _todosById.values.toList(growable: false);

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async =>
      const <TodoChecklistProgress>[];

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    if (sharedTaskPriorityAssessmentsJson == null) {
      throw UnimplementedError('fetchTaskPriorityAiAssessmentsCloudGateway');
    }
    return sharedTaskPriorityAssessmentsJson!;
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    if (taskPriorityAiResponseJson == null) {
      throw UnimplementedError('taskPriorityRerankAi');
    }
    return taskPriorityAiResponseJson!;
  }
}
