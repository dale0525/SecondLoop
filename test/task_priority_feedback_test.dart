import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_feedback_store.dart';

void main() {
  test('records suppression and deprioritization feedback', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TaskPriorityFeedbackStore();

    await store.record(
      todoId: 'todo-1',
      feedback: TaskPriorityFeedbackKind.notImportant,
    );

    final state = await store.read();
    expect(state.suppressedTodoIds, contains('todo-1'));
    expect(state.deprioritizedTodoIds, contains('todo-1'));
  });

  test('prune removes stale feedback ids', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TaskPriorityFeedbackStore();

    await store.record(
      todoId: 'todo-keep',
      feedback: TaskPriorityFeedbackKind.notImportant,
    );
    await store.record(
      todoId: 'todo-drop',
      feedback: TaskPriorityFeedbackKind.recommendLater,
    );

    await store.pruneToTodoIds(const <String>['todo-keep']);

    final state = await store.read();
    expect(state.suppressedTodoIds, contains('todo-keep'));
    expect(state.suppressedTodoIds, isNot(contains('todo-drop')));
    expect(state.deprioritizedTodoIds, contains('todo-keep'));
  });

  test('later and decide-myself feedback suppress future recommendation',
      () async {
    SharedPreferences.setMockInitialValues({});
    const store = TaskPriorityFeedbackStore();

    await store.record(
      todoId: 'todo-2',
      feedback: TaskPriorityFeedbackKind.recommendLater,
    );
    await store.record(
      todoId: 'todo-3',
      feedback: TaskPriorityFeedbackKind.decideMyself,
    );

    final state = await store.read();
    expect(state.suppressedTodoIds, containsAll(<String>['todo-2', 'todo-3']));
  });
}
