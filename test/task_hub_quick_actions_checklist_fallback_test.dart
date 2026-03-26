import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/src/rust/db.dart';

import 'task_hub_quick_actions_test_helpers.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    String status = 'open',
  }) {
    return Todo(
      id: id,
      title: title,
      status: status,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
    );
  }

  test(
      'done action falls back to checklist items when progress cache is missing',
      () async {
    SharedPreferences.setMockInitialValues({});

    final initial =
        todo(id: 'todo:checklist', title: 'Checklist task', updatedAtMs: 1);
    final backend = QuickActionBackendTestDouble(
      initialTodos: <Todo>[initial],
      checklistItemsByTodoId: <String, List<TodoChecklistItem>>{
        'todo:checklist': const <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'item:1',
            todoId: 'todo:checklist',
            content: 'Still pending',
            sortOrder: 0,
            isDone: false,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      },
    );

    var confirmCalls = 0;
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: Uint8List(32),
      confirmDoneWithIncompleteChecklist: (_) async {
        confirmCalls += 1;
        return false;
      },
    );

    final ticket = await controller.apply(initial, TaskHubQuickAction.done);

    expect(ticket, isNull);
    expect(confirmCalls, 1);
    expect(backend.current('todo:checklist').status, 'open');
  });
}
