import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend auto-enqueues follow-up job on first todo create',
      () async {
    var existingTodos = <Todo>[];
    var enqueueCount = 0;
    var listTodosCalls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListTodos: ({required String appDir, required List<int> key}) async {
        listTodosCalls += 1;
        return List<Todo>.from(existingTodos);
      },
      dbUpsertTodo: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
      }) async {
        final existed = existingTodos.any((todo) => todo.id == id);
        final todo = Todo(
          id: id,
          title: title,
          dueAtMs: dueAtMs,
          status: status,
          sourceEntryId: sourceEntryId,
          createdAtMs: 1,
          updatedAtMs: existed ? 2 : 1,
          reviewStage: reviewStage,
          nextReviewAtMs: nextReviewAtMs,
          lastReviewAtMs: lastReviewAtMs,
        );
        existingTodos = <Todo>[todo];
        return todo;
      },
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        enqueueCount += 1;
        expect(manualOverrideFollowup, isFalse);
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));

    await backend.upsertTodo(
      key,
      id: 'todo_1',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
    );

    expect(enqueueCount, 1);
    expect(listTodosCalls, 0);

    await backend.upsertTodo(
      key,
      id: 'todo_1',
      title: '调研一下当前主流的 llm 模型（更新）',
      status: 'open',
    );

    expect(enqueueCount, 1);
    expect(listTodosCalls, 0);
  });

  test('NativeAppBackend skips auto-enqueue for execution-focused todo create',
      () async {
    var enqueueCount = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbUpsertTodo: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
      }) async =>
          Todo(
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        createdAtMs: 1,
        updatedAtMs: 1,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
      ),
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        enqueueCount += 1;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 17));

    await backend.upsertTodo(
      key,
      id: 'todo_execution',
      title: '修复登录页闪退',
      status: 'open',
    );

    expect(enqueueCount, 0);
  });

  test('NativeAppBackend ignores auto-enqueue failures after todo create',
      () async {
    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbUpsertTodo: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
      }) async =>
          Todo(
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        createdAtMs: 1,
        updatedAtMs: 1,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
      ),
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        throw StateError('queue unavailable');
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final todo = await backend.upsertTodo(
      key,
      id: 'todo_2',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
    );

    expect(todo.id, 'todo_2');
    expect(todo.title, '调研一下当前主流的 llm 模型');
  });

  test(
      'NativeAppBackend semantic create forwards taskTypeHint without double enqueue',
      () async {
    final enqueueTaskTypeHints = <String?>[];

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbUpsertTodo: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
      }) async =>
          Todo(
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        createdAtMs: 1,
        updatedAtMs: 1,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
      ),
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        expect(manualOverrideFollowup, isFalse);
        enqueueTaskTypeHints.add(taskTypeHint);
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final todo = await backend.upsertTodoFromSemanticCreate(
      key,
      id: 'todo_semantic',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
      sourceEntryId: 'm1',
      followupTaskTypeHint: 'research',
    );

    expect(todo.id, 'todo_semantic');
    expect(enqueueTaskTypeHints, const <String?>['research']);
  });

  test('NativeAppBackend uses dedicated auto-job query path', () async {
    var mixedQueryCalls = 0;
    var autoQueryCalls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListDueTodoFollowupGenerationJobs: ({
        required String appDir,
        required List<int> key,
        required int nowMs,
        required int limit,
      }) async {
        mixedQueryCalls += 1;
        return const <TodoFollowupGenerationJob>[
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
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ];
      },
      dbListDueAutoTodoFollowupGenerationJobs: ({
        required String appDir,
        required List<int> key,
        required int nowMs,
        required int limit,
      }) async {
        autoQueryCalls += 1;
        return const <TodoFollowupGenerationJob>[
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
            createdAtMs: 2,
            updatedAtMs: 2,
          ),
        ];
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final jobs = await backend.listDueAutoTodoFollowupGenerationJobs(
      key,
      nowMs: 123,
      limit: 1,
    );

    expect(
      jobs.map((job) => job.todoId).toList(growable: false),
      const <String>['todo_auto'],
    );
    expect(autoQueryCalls, 1);
    expect(mixedQueryCalls, 0);
  });

  test('NativeAppBackend uses atomic create+enqueue path for new todos',
      () async {
    var atomicCallCount = 0;
    var enqueueCallCount = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbUpsertTodoWithAutoFollowupJob: ({
        required String appDir,
        required List<int> key,
        required String id,
        required String title,
        int? dueAtMs,
        required String status,
        String? sourceEntryId,
        int? reviewStage,
        int? nextReviewAtMs,
        int? lastReviewAtMs,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        atomicCallCount += 1;
        return Todo(
          id: id,
          title: title,
          dueAtMs: dueAtMs,
          status: status,
          sourceEntryId: sourceEntryId,
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: reviewStage,
          nextReviewAtMs: nextReviewAtMs,
          lastReviewAtMs: lastReviewAtMs,
        );
      },
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        enqueueCallCount += 1;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final todo = await backend.upsertTodoFromSemanticCreate(
      key,
      id: 'todo_atomic',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
      followupTaskTypeHint: 'research',
    );

    expect(todo.id, 'todo_atomic');
    expect(atomicCallCount, 1);
    expect(enqueueCallCount, 0);
  });
}
