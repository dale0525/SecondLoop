import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/settings/llm_profiles_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

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

  testWidgets('task hub done quick action notifies sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'ship this',
          status: 'in_progress',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: null,
          nextReviewAtMs: null,
        ),
      ],
    );

    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester.pumpWidget(
      SyncEngineScope(
        engine: engine,
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: TaskHubPage()),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_quick_todo:1_done')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_done')));
    await _pumpUntil(
      tester,
      () => backend.transitionTodoCalls >= 1 && changes >= 1,
    );

    expect(backend.transitionTodoCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
  });

  testWidgets('task hub tomorrow quick action notifies sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'prepare draft',
          status: 'open',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: null,
          nextReviewAtMs: null,
        ),
      ],
    );

    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester.pumpWidget(
      SyncEngineScope(
        engine: engine,
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: TaskHubPage()),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);

    await _pumpUntil(
      tester,
      () => backend.transitionTodoCalls >= 1 && changes >= 1,
    );

    expect(backend.transitionTodoCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
    expect(find.text('prepare draft'), findsWidgets);
  });

  testWidgets('activating an llm profile notifies sync engine', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _TaskHubBackend(
      todos: const <Todo>[],
      llmProfiles: <LlmProfile>[
        const LlmProfile(
          id: 'profile-a',
          name: 'Profile A',
          providerType: 'openai-compatible',
          baseUrl: 'https://a.example',
          modelName: 'model-a',
          isActive: true,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        const LlmProfile(
          id: 'profile-b',
          name: 'Profile B',
          providerType: 'openai-compatible',
          baseUrl: 'https://b.example',
          modelName: 'model-b',
          isActive: false,
          createdAtMs: 2,
          updatedAtMs: 2,
        ),
      ],
    );

    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester.pumpWidget(
      SyncEngineScope(
        engine: engine,
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: LlmProfilesPage()),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Profile B'));

    await tester.tap(find.text('Profile B'));
    await _pumpUntil(
      tester,
      () => backend.setActiveLlmProfileCalls >= 1 && changes >= 1,
    );

    expect(backend.setActiveLlmProfileCalls, 1);
    expect(changes, greaterThanOrEqualTo(1));
  });

  testWidgets('task hub refreshes after sync engine reports external changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'Old title',
          status: 'open',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: null,
          nextReviewAtMs: null,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );

    await tester.pumpWidget(
      SyncEngineScope(
        engine: engine,
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: TaskHubPage()),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Old title'));

    backend.replaceTodo(
      Todo(
        id: 'todo:1',
        title: 'Updated title',
        status: 'open',
        createdAtMs: nowUtcMs - 1000,
        updatedAtMs: nowUtcMs,
        reviewStage: null,
        nextReviewAtMs: null,
      ),
    );
    engine.notifyExternalChange();

    await _pumpUntilFound(tester, find.text('Updated title'));
  });

  testWidgets(
      'task hub quick action snackbar auto dismisses with accessible navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'prepare draft',
          status: 'open',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: null,
          nextReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      SyncEngineScope(
        engine: SyncEngine(
          syncRunner: _NoopSyncRunner(),
          loadConfig: () async => null,
          pullOnStart: false,
        ),
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(accessibleNavigation: true),
                  child: child!,
                ),
                home: const TaskHubPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'task hub quick action snackbar does not linger after leaving page',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'actions.review.day_end_minutes_v1': (23 * 60) + 59,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backend = _TaskHubBackend(
      todos: <Todo>[
        Todo(
          id: 'todo:1',
          title: 'prepare draft',
          status: 'open',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: null,
          nextReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      SyncEngineScope(
        engine: SyncEngine(
          syncRunner: _NoopSyncRunner(),
          loadConfig: () async => null,
          pullOnStart: false,
        ),
        child: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Home')),
                    body: Center(
                      child: ElevatedButton(
                        key: const ValueKey('open_task_hub_page'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TaskHubPage(),
                            ),
                          );
                        },
                        child: const Text('Open task hub'),
                      ),
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
      find.byKey(const ValueKey('open_task_hub_page')),
    );

    await tester.tap(find.byKey(const ValueKey('open_task_hub_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')),
    );

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_todo:1_tomorrow')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('open_task_hub_page')),
    );

    await _pumpUntil(
      tester,
      () => find.byType(SnackBar).evaluate().isEmpty,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _TaskHubBackend implements AppBackend {
  _TaskHubBackend({required List<Todo> todos, List<LlmProfile>? llmProfiles})
      : _todosById = <String, Todo>{
          for (final todo in todos) todo.id: todo,
        },
        _llmProfiles = List<LlmProfile>.from(
          llmProfiles ?? const <LlmProfile>[],
        );

  final Map<String, Todo> _todosById;
  final List<LlmProfile> _llmProfiles;
  int upsertTodoCalls = 0;
  int transitionTodoCalls = 0;
  int setTodoStatusCalls = 0;
  int setActiveLlmProfileCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      _todosById.values.toList(growable: false);

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
    upsertTodoCalls += 1;
    final existing = _todosById[id];
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final todo = Todo(
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
          _todosById[id]?.manualImportanceNudgeScore ??
          0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ??
          _todosById[id]?.manualUrgencyNudgeScore ??
          0,
    );
    _todosById[id] = todo;
    return todo;
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
    transitionTodoCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) throw StateError('todo missing: $todoId');
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final todo = Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? existing.dueAtMs),
      status: newStatus ?? existing.status,
      sourceEntryId: existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: nowMs,
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
    _todosById[todoId] = todo;
    return todo;
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_llmProfiles);

  void replaceTodo(Todo todo) {
    _todosById[todo.id] = todo;
  }

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {
    setActiveLlmProfileCalls += 1;
    for (var i = 0; i < _llmProfiles.length; i += 1) {
      final profile = _llmProfiles[i];
      _llmProfiles[i] = LlmProfile(
        id: profile.id,
        name: profile.name,
        providerType: profile.providerType,
        baseUrl: profile.baseUrl,
        modelName: profile.modelName,
        isActive: profile.id == profileId,
        createdAtMs: profile.createdAtMs,
        updatedAtMs: profile.updatedAtMs,
      );
    }
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) throw StateError('todo missing: $todoId');
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
    );
    _todosById[todoId] = updated;
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
