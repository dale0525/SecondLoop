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

  test('AppBackend semantic create skips follow-up enqueue for existing todos',
      () async {
    final backend = _FollowupCapabilityBackend(wasCreated: false);
    final key = Uint8List.fromList(List<int>.filled(32, 9));

    final todo = await backend.upsertTodoFromSemanticCreate(
      key,
      id: 'todo_existing',
      title: 'Refine an existing task',
      status: 'open',
      followupTaskTypeHint: 'research',
    );

    expect(todo.id, 'todo_existing');
    expect(backend.enqueueTodoIds, isEmpty);
    expect(backend.enqueueTaskTypeHints, isEmpty);
    expect(backend.enqueueTriggerKinds, isEmpty);
  });

  test(
      'AppBackend semantic create avoids duplicate enqueue when backend already auto-enqueues',
      () async {
    final backend = _FollowupCapabilityBackend(autoEnqueuesOnCreate: true);
    final key = Uint8List.fromList(List<int>.filled(32, 11));

    final todo = await backend.upsertTodoFromSemanticCreate(
      key,
      id: 'todo_auto',
      title: 'Collect conference notes',
      status: 'inbox',
      followupTaskTypeHint: 'research',
    );

    expect(todo.id, 'todo_auto');
    expect(backend.enqueueTodoIds, const <String>['todo_auto']);
    expect(backend.enqueueTaskTypeHints, const <String?>[null]);
    expect(backend.enqueueTriggerKinds, const <String>['auto_create']);
  });

  test('createTodoWithFollowup auto-enqueues for capability backends',
      () async {
    final backend = _FollowupCapabilityBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 3));

    final todo = await createTodoWithFollowup(
      backend,
      key,
      id: 'todo_2',
      title: 'Compare current coding agents',
      status: 'open',
    );

    expect(todo.id, 'todo_2');
    expect(backend.enqueueTodoIds, const <String>['todo_2']);
    expect(backend.enqueueTaskTypeHints, const <String?>[null]);
    expect(backend.enqueueTriggerKinds, const <String>['auto_create']);
  });

  test(
      'createTodoWithFollowup avoids duplicate enqueue when backend already auto-enqueues',
      () async {
    final backend = _FollowupCapabilityBackend(autoEnqueuesOnCreate: true);
    final key = Uint8List.fromList(List<int>.filled(32, 5));

    final todo = await createTodoWithFollowup(
      backend,
      key,
      id: 'todo_3',
      title: 'Collect conference notes',
      status: 'inbox',
    );

    expect(todo.id, 'todo_3');
    expect(backend.enqueueTodoIds, const <String>['todo_3']);
    expect(backend.enqueueTaskTypeHints, const <String?>[null]);
    expect(backend.enqueueTriggerKinds, const <String>['auto_create']);
  });
}

final class _FollowupCapabilityBackend extends AppBackend {
  _FollowupCapabilityBackend({
    this.autoEnqueuesOnCreate = false,
    this.wasCreated = true,
  });

  final List<String> enqueueTodoIds = <String>[];
  final List<String?> enqueueTaskTypeHints = <String?>[];
  final List<String> enqueueTriggerKinds = <String>[];
  final bool autoEnqueuesOnCreate;
  final bool wasCreated;

  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  bool get autoEnqueuesTodoFollowupGenerationOnCreate => autoEnqueuesOnCreate;

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
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    if (autoEnqueuesOnCreate) {
      enqueueTodoIds.add(id);
      enqueueTaskTypeHints.add(null);
      enqueueTriggerKinds.add('auto_create');
    }
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 1,
      updatedAtMs: wasCreated ? 1 : 2,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
  }

  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    bool manualOverrideFollowup = false,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueueTodoIds.add(todoId);
    enqueueTaskTypeHints.add(taskTypeHint);
    enqueueTriggerKinds.add(triggerKind);
  }
}
