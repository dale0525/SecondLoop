import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

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

  testWidgets('TodoAgendaBanner shows checklist progress in preview rows',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: TodoAgendaBanner(
              dueCount: 1,
              overdueCount: 0,
              upcomingCount: 0,
              previewTodos: <Todo>[
                Todo(
                  id: 'todo:banner',
                  title: 'Prepare launch notes',
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
              checklistProgressByTodoId: <String, TodoChecklistProgress>{
                'todo:banner': TodoChecklistProgress(
                  todoId: 'todo:banner',
                  totalCount: 3,
                  doneCount: 1,
                ),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_agenda_checklist_progress_todo:banner')),
      findsOneWidget,
    );
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('Chat page shows task hub banner for unscheduled todos',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: [
        const Todo(
          id: 'todo:inbox',
          title: 'Plan quarterly review',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
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
                  id: 'main_stream',
                  title: 'Main Stream',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_agenda_banner')), findsNothing);
    expect(
        find.byKey(const ValueKey('todo_undetermined_banner')), findsNothing);
  });

  testWidgets('Task hub banner expands and view all opens task hub page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final dueLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
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
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner_view_all')),
    );

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task_hub_banner_view_all')));
    await tester.pumpAndSettle();

    expect(find.byType(TaskHubPage), findsOneWidget);
  });

  testWidgets('Task hub banner task row opens todo detail page in chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: const [
        Todo(
          id: 'todo:detail',
          title: 'Open detail from banner',
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
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner_item_todo:detail')),
    );

    final bannerItem =
        find.byKey(const ValueKey('task_hub_banner_item_todo:detail'));
    expect(bannerItem, findsOneWidget);
    await tester.tap(bannerItem);
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailPage), findsOneWidget);
  });

  testWidgets('Task hub banner stays expanded after 10 seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final dueLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);
  });

  testWidgets(
      'Task hub banner quick action snackbar auto dismisses with accessible navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: [
        const Todo(
          id: 'todo:snack',
          title: 'Review metrics',
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
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
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
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_primary_action')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'Task hub banner quick action snackbar does not linger after page is replaced',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: [
        const Todo(
          id: 'todo:snack',
          title: 'Review metrics',
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
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Home')),
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_chat_page'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey:
                                Uint8List.fromList(List<int>.filled(32, 1)),
                            lock: () {},
                            child: const ChatPage(
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
                    );
                  },
                  child: const Text('Open chat'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_chat_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_banner_primary_action')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Chat task hub banner shows shared ai source label',
      (tester) async {
    final nowLocal = DateTime.now();
    final requestSignature = jsonEncode(<String, Object?>{
      'time_bucket': buildTaskPriorityAiTimeBucket(nowLocal),
      'candidate': buildTaskPriorityAiRequest(
        buildTaskPrioritySnapshot(
          <Todo>[
            const Todo(
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
            ),
          ],
          nowLocal: nowLocal,
        ),
        nowLocal: nowLocal,
      ).candidates.single.toJson(),
    });

    final backend = _AgendaBackend(
      todos: const [
        Todo(
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
        ),
      ],
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
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
    );

    expect(find.text('Shared AI insight'), findsOneWidget);
    expect(find.text('Shared AI result.'), findsOneWidget);
  });

  testWidgets('Chat task hub banner shows cached local ai source label',
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
    final requestSignature = jsonEncode(<String, Object?>{
      'time_bucket': buildTaskPriorityAiTimeBucket(nowLocal),
      'candidate': buildTaskPriorityAiRequest(
        buildTaskPrioritySnapshot(
          <Todo>[
            const Todo(
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
            ),
          ],
          nowLocal: nowLocal,
        ),
        nowLocal: nowLocal,
      ).candidates.single.toJson(),
    });
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
      todos: const [
        Todo(
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
        ),
      ],
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
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
    );

    expect(find.text('Cached AI insight'), findsOneWidget);
    expect(find.text('Cached AI result.'), findsOneWidget);
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
      find.byKey(const ValueKey('task_hub_banner_ai_source')),
    );

    expect(find.text('Live AI insight'), findsOneWidget);
    expect(find.text('Live AI result.'), findsOneWidget);
  });

  testWidgets(
      'Task hub banner primary action shows the new urgency label in chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: const [
        Todo(
          id: 'todo:label',
          title: 'Backlog follow-up',
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
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
    );

    expect(
      find.byKey(const ValueKey('task_hub_banner_primary_action')),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
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
  }) : _todosById = <String, Todo>{
          for (final todo in todos) todo.id: todo,
        };

  final Map<String, Todo> _todosById;
  final String? taskPriorityAiResponseJson;
  final String? sharedTaskPriorityAssessmentsJson;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      _todosById.values.toList(growable: false);

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async =>
      const <TodoChecklistProgress>[];

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
    final existing = _todosById[id];
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ??
          existing?.manualImportanceNudgeScore ??
          0,
      manualUrgencyNudgeScore:
          manualUrgencyNudgeScore ?? existing?.manualUrgencyNudgeScore ?? 0,
    );
    _todosById[id] = updated;
    return updated;
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
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('todo missing: $todoId');
    }
    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? existing.dueAtMs),
      status: newStatus ?? existing.status,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage:
          clearReviewStage ? null : (reviewStage ?? existing.reviewStage),
      nextReviewAtMs: clearNextReviewAtMs
          ? null
          : (nextReviewAtMs ?? existing.nextReviewAtMs),
      lastReviewAtMs: clearLastReviewAtMs
          ? null
          : (lastReviewAtMs ?? existing.lastReviewAtMs),
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? 0
          : (manualImportanceNudgeScore ??
              existing.manualImportanceNudgeScore ??
              0),
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? 0
          : (manualUrgencyNudgeScore ?? existing.manualUrgencyNudgeScore ?? 0),
    );
    _todosById[todoId] = updated;
    return updated;
  }

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

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('todo missing: $todoId');
    }
    final updated = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: newStatus,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
      manualImportanceNudgeScore: existing.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: existing.manualUrgencyNudgeScore,
    );
    _todosById[todoId] = updated;
    return updated;
  }
}
