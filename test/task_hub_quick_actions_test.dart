import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
    int? reviewStage,
    int? nextReviewAtMs,
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
      lastReviewAtMs: null,
    );
  }

  test('applies today and can undo to original todo', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't1', title: 'Task 1', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.today);
    expect(ticket, isNotNull);
    final afterToday = backend.current('t1');
    expect(afterToday.status, 'open');
    expect(afterToday.dueAtMs, isNotNull);
    expect(afterToday.reviewStage, isNull);
    expect(afterToday.nextReviewAtMs, isNull);

    await controller.undo(ticket!);
    final restored = backend.current('t1');
    expect(restored.status, initial.status);
    expect(restored.dueAtMs, initial.dueAtMs);
    expect(restored.reviewStage, initial.reviewStage);
    expect(restored.nextReviewAtMs, initial.nextReviewAtMs);
  });

  test('later action pushes todo back to inbox review queue', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't2', title: 'Task 2', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.later);
    expect(ticket, isNotNull);
    final updated = backend.current('t2');
    expect(updated.status, 'inbox');
    expect(updated.dueAtMs, isNull);
    expect(updated.reviewStage, 0);
    expect(updated.nextReviewAtMs, isNotNull);
  });

  test('done action sets status to done', () async {
    SharedPreferences.setMockInitialValues({});

    final initial = todo(id: 't3', title: 'Task 3', updatedAtMs: 10);
    final backend = _QuickActionBackend(initialTodos: [initial]);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);
    expect(ticket, isNotNull);
    expect(backend.current('t3').status, 'done');
  });
}

final class _QuickActionBackend extends AppBackend {
  _QuickActionBackend({List<Todo>? initialTodos})
      : _todosById = {
          for (final todo in initialTodos ?? const <Todo>[]) todo.id: todo,
        };

  final Map<String, Todo> _todosById;

  Todo current(String id) => _todosById[id]!;

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
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: _todosById[id]?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todosById[id] = updated;
    return updated;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todosById[todoId]!;
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
