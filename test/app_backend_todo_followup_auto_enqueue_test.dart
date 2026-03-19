import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('AppBackend semantic create auto-enqueues even without task hint',
      () async {
    final backend = _FollowupCapabilityBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 7));

    final todo = await backend.upsertTodoFromSemanticCreate(
      key,
      id: 'todo_1',
      title: '调研一下当前主流的 llm 模型',
      status: 'open',
      followupTaskTypeHint: null,
    );

    expect(todo.id, 'todo_1');
    expect(backend.enqueueTodoIds, const <String>['todo_1']);
    expect(backend.enqueueTaskTypeHints, const <String?>[null]);
    expect(backend.enqueueTriggerKinds, const <String>['auto_create']);
  });
}

final class _FollowupCapabilityBackend extends AppBackend {
  final List<String> enqueueTodoIds = <String>[];
  final List<String?> enqueueTaskTypeHints = <String?>[];
  final List<String> enqueueTriggerKinds = <String>[];

  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
      );

  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueueTodoIds.add(todoId);
    enqueueTaskTypeHints.add(taskTypeHint);
    enqueueTriggerKinds.add(triggerKind);
  }
}
