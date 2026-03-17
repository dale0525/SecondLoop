import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend auto-enqueues follow-up job on first todo create',
      () async {
    var existingTodos = <Todo>[];
    var enqueueCount = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListTodos: ({required String appDir, required List<int> key}) async {
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
        final todo = Todo(
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
        existingTodos = <Todo>[todo];
        return todo;
      },
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        enqueueCount += 1;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));

    await backend.upsertTodo(
      key,
      id: 'todo_1',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
    );
    await Future<void>.delayed(Duration.zero);

    expect(enqueueCount, 1);

    await backend.upsertTodo(
      key,
      id: 'todo_1',
      title: '调研一下当前主流的 llm 模型（更新）',
      status: 'open',
    );
    await Future<void>.delayed(Duration.zero);

    expect(enqueueCount, 1);
  });
}
