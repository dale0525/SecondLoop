import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';

void main() {
  setUp(TaskPrioritySignalStore.resetMutationQueueForTest);

  test('memory signal store keeps signed importance and urgency scores',
      () async {
    final store = _MemorySignalStore();
    await store.setForTodo(
      'todo:1',
      const TaskPriorityManualSignal(
        importanceScore: 2,
        urgencyScore: -3,
      ),
    );

    final signal = await store.readForTodo('todo:1');

    expect(signal, isNotNull);
    expect(signal?.importanceScore, 2);
    expect(signal?.urgencyScore, -3);
  });

  test('manual signal migrates legacy bool overrides into scores', () {
    final signal = TaskPriorityManualSignal.fromJson(
      const <String, Object?>{
        'is_important': true,
        'is_urgent': false,
      },
    );

    expect(signal.importanceScore, 1);
    expect(signal.urgencyScore, -1);
  });

  test('concurrent mutations for different todos preserve both updates',
      () async {
    final store = _MemorySignalStore();
    await Future.wait<void>([
      store.mutateForTodo(
        'todo:a',
        (current) => current.copyWith(importanceDelta: 1),
      ),
      store.mutateForTodo(
        'todo:b',
        (current) => current.copyWith(urgencyDelta: 1),
      ),
    ]);

    final signalA = await store.readForTodo('todo:a');
    final signalB = await store.readForTodo('todo:b');

    expect(signalA?.importanceScore, 1);
    expect(signalB?.urgencyScore, 1);
  });

  test('clearPreferredStatusForTodo preserves concurrent score updates',
      () async {
    final store = _InterleavingSignalStore(
      const TaskPriorityManualSignal(
        importanceScore: 1,
        preferredStatus: 'in_progress',
      ),
    );

    final clearFuture = store.clearPreferredStatusForTodo('todo:1');
    await store.clearStarted.future;

    await store.mutateForTodo(
      'todo:1',
      (current) => current.copyWith(urgencyDelta: 1),
    );
    store.allowClearMutation.complete();

    final previous = await clearFuture;
    final updated = await store.readForTodo('todo:1');

    expect(previous?.preferredStatus, 'in_progress');
    expect(updated?.preferredStatus, isNull);
    expect(updated?.importanceScore, 1);
    expect(updated?.urgencyScore, 1);
  });
}

class _MemorySignalStore extends TaskPrioritySignalStore {
  _MemorySignalStore();

  final Map<String, TaskPriorityManualSignal> _signals =
      <String, TaskPriorityManualSignal>{};
  Future<void> _pending = Future<void>.value();

  Future<T> _enqueue<T>(FutureOr<T> Function() action) {
    final result = Completer<T>();
    _pending = _pending.catchError((_) {}).then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  @override
  Future<TaskPriorityManualSignal?> readForTodo(String todoId) async {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return null;
    return _signals[trimmedTodoId];
  }

  @override
  Future<void> setForTodo(String todoId, TaskPriorityManualSignal signal) {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) return Future<void>.value();
    return _enqueue<void>(() {
      if (signal.isEmpty) {
        _signals.remove(trimmedTodoId);
      } else {
        _signals[trimmedTodoId] = signal;
      }
    });
  }

  @override
  Future<TaskPrioritySignalMutation> mutateForTodo(
    String todoId,
    TaskPriorityManualSignal Function(TaskPriorityManualSignal current) mutate,
  ) {
    final trimmedTodoId = todoId.trim();
    if (trimmedTodoId.isEmpty) {
      return Future.value(
        const TaskPrioritySignalMutation(
          previous: null,
          updated: TaskPriorityManualSignal(),
        ),
      );
    }
    return _enqueue<TaskPrioritySignalMutation>(() {
      final previous = _signals[trimmedTodoId];
      final updated = mutate(previous ?? const TaskPriorityManualSignal());
      if (updated.isEmpty) {
        _signals.remove(trimmedTodoId);
      } else {
        _signals[trimmedTodoId] = updated;
      }
      return TaskPrioritySignalMutation(previous: previous, updated: updated);
    });
  }
}

final class _InterleavingSignalStore extends TaskPrioritySignalStore {
  _InterleavingSignalStore(this._signal);

  TaskPriorityManualSignal? _signal;
  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> allowClearMutation = Completer<void>();
  var _clearMutationPending = false;

  @override
  Future<TaskPriorityManualSignal?> readForTodo(String todoId) async {
    if (!clearStarted.isCompleted) {
      clearStarted.complete();
    }
    return _signal;
  }

  @override
  Future<TaskPrioritySignalMutation> mutateForTodo(
    String todoId,
    TaskPriorityManualSignal Function(TaskPriorityManualSignal current) mutate,
  ) async {
    if (!_clearMutationPending && !clearStarted.isCompleted) {
      _clearMutationPending = true;
      clearStarted.complete();
      await allowClearMutation.future;
    }
    final previous = _signal;
    final updated = mutate(previous ?? const TaskPriorityManualSignal());
    _signal = updated.isEmpty ? null : updated;
    return TaskPrioritySignalMutation(previous: previous, updated: updated);
  }
}
