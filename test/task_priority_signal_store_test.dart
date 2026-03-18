import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';

void main() {
  test('signal store persists signed importance and urgency scores', () async {
    SharedPreferences.setMockInitialValues({});

    const store = TaskPrioritySignalStore();
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

  test('signal store migrates legacy bool overrides into scores', () async {
    SharedPreferences.setMockInitialValues({
      'task_priority_manual_signals_v1':
          '{"todos":{"todo:legacy":{"is_important":true,"is_urgent":false}}}',
    });

    const store = TaskPrioritySignalStore();
    final signal = await store.readForTodo('todo:legacy');

    expect(signal, isNotNull);
    expect(signal?.importanceScore, 1);
    expect(signal?.urgencyScore, -1);
  });
}
