import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void clearTaskHubSharedAiCacheForTest() {
  BackendTaskPriorityAiService.clearSharedCacheForTest();
}

Future<void> pumpUntil(
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

Future<void> pumpUntilFound(
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

Future<void> pumpUntilTaskHubReady(WidgetTester tester) {
  return pumpUntil(
    tester,
    () =>
        find.byKey(const ValueKey('task_hub_page')).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
}

VoidCallback useLargeViewport(WidgetTester tester) {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  var cleanedUp = false;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  }

  addTearDown(cleanup);
  return cleanup;
}

Widget wrapTaskHubTestApp(
  AppBackend backend, {
  SyncEngine? syncEngine,
  MediaQueryData? mediaQueryData,
}) {
  Widget page = const TaskHubPage();
  if (mediaQueryData != null) {
    page = MediaQuery(
      data: mediaQueryData,
      child: page,
    );
  }
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: syncEngine,
            child: page,
          ),
        ),
      ),
    ),
  );
}

final class TaskHubTestBackend extends TestAppBackend {
  TaskHubTestBackend({
    required List<Todo> todos,
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    this.failTransition = false,
    this.taskPriorityAiResponseJson,
    this.taskPriorityAiResponseCompleter,
    List<Future<String> Function()> taskPriorityAiResponseCallbacks =
        const <Future<String> Function()>[],
    List<Future<String>> taskPriorityAiResponseFutures =
        const <Future<String>>[],
    this.listTodosDelay = Duration.zero,
    List<LlmProfile>? llmProfiles,
  })  : _todos = {for (final todo in todos) todo.id: todo},
        _checklistProgress =
            List<TodoChecklistProgress>.from(checklistProgress),
        _taskPriorityAiResponseCallbacks = List<Future<String> Function()>.from(
            taskPriorityAiResponseCallbacks),
        _taskPriorityAiResponseFutures =
            List<Future<String>>.from(taskPriorityAiResponseFutures),
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

  final Map<String, Todo> _todos;
  int listTodosCallCount = 0;
  final List<TodoChecklistProgress> _checklistProgress;
  final List<Future<String> Function()> _taskPriorityAiResponseCallbacks;
  int _taskPriorityAiResponseCallbackIndex = 0;
  final List<Future<String>> _taskPriorityAiResponseFutures;
  int _taskPriorityAiResponseFutureIndex = 0;
  final List<LlmProfile> _llmProfiles;
  final bool failTransition;
  final String? taskPriorityAiResponseJson;
  final Completer<String>? taskPriorityAiResponseCompleter;
  int taskPriorityAiCallCount = 0;
  Duration listTodosDelay;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_llmProfiles);

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    if (listTodosDelay > Duration.zero) {
      await Future<void>.delayed(listTodosDelay);
    }
    listTodosCallCount += 1;
    return _todos.values.toList(growable: false);
  }

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async {
    return List<TodoChecklistProgress>.from(_checklistProgress);
  }

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
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todos[id]?.createdAtMs ?? 0,
      updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ??
          _todos[id]?.manualImportanceNudgeScore ??
          0,
      manualUrgencyNudgeScore:
          manualUrgencyNudgeScore ?? _todos[id]?.manualUrgencyNudgeScore ?? 0,
    );
    _todos[id] = updated;
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
    if (failTransition) {
      throw StateError('apply failed');
    }
    final existing = _todos[todoId]!;
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
    _todos[todoId] = updated;
    return updated;
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    taskPriorityAiCallCount += 1;
    if (taskPriorityAiCallCount == 1 && taskPriorityAiResponseJson != null) {
      return taskPriorityAiResponseJson!;
    }
    if (_taskPriorityAiResponseCallbackIndex <
        _taskPriorityAiResponseCallbacks.length) {
      return _taskPriorityAiResponseCallbacks[
          _taskPriorityAiResponseCallbackIndex++]();
    }
    if (_taskPriorityAiResponseFutureIndex <
        _taskPriorityAiResponseFutures.length) {
      return _taskPriorityAiResponseFutures[
          _taskPriorityAiResponseFutureIndex++];
    }
    final completer = taskPriorityAiResponseCompleter;
    if (completer != null) {
      return completer.future;
    }
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
    final existing = _todos[todoId]!;
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
    _todos[todoId] = updated;
    return updated;
  }
}

final class NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}
