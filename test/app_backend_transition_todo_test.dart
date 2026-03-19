import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
  }

  test('default transitionTodo falls back to status change plus field patch',
      () async {
    final backend = _FallbackTransitionBackend(
      todo(
        id: 'todo:1',
        title: 'Task',
        updatedAtMs: 10,
        status: 'open',
        dueAtMs: 111,
        reviewStage: 2,
        nextReviewAtMs: 222,
      ),
    );

    final updated = await backend.transitionTodo(
      Uint8List(32),
      todoId: 'todo:1',
      newStatus: 'in_progress',
      dueAtMs: 333,
      reviewStage: 4,
      nextReviewAtMs: 444,
      lastReviewAtMs: 555,
    );

    expect(updated.status, 'in_progress');
    expect(updated.dueAtMs, 333);
    expect(updated.reviewStage, 4);
    expect(updated.nextReviewAtMs, 444);
    expect(updated.lastReviewAtMs, 555);
    expect(backend.setTodoStatusCalls, 1);
    expect(backend.upsertTodoCalls, 1);
  });
}

final class _FallbackTransitionBackend extends TestAppBackend {
  _FallbackTransitionBackend(this._todo);

  Todo _todo;
  var setTodoStatusCalls = 0;
  var upsertTodoCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => <Todo>[_todo];

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
  }) async {
    upsertTodoCalls += 1;
    _todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todo.createdAtMs,
      updatedAtMs: _todo.updatedAtMs + 1,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    return _todo;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    _todo = Todo(
      id: _todo.id,
      title: _todo.title,
      dueAtMs: _todo.dueAtMs,
      status: newStatus,
      sourceEntryId: _todo.sourceEntryId,
      createdAtMs: _todo.createdAtMs,
      updatedAtMs: _todo.updatedAtMs + 1,
      reviewStage: _todo.reviewStage,
      nextReviewAtMs: _todo.nextReviewAtMs,
      lastReviewAtMs: _todo.lastReviewAtMs,
    );
    return _todo;
  }
}
