import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

Todo todo({
  required String id,
  required String title,
  required int updatedAtMs,
  int? manualImportanceNudgeScore,
  int? manualUrgencyNudgeScore,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: null,
    status: 'open',
    sourceEntryId: null,
    createdAtMs: updatedAtMs,
    updatedAtMs: updatedAtMs,
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
    manualImportanceNudgeScore: manualImportanceNudgeScore,
    manualUrgencyNudgeScore: manualUrgencyNudgeScore,
  );
}

void main() {
  test('manual move-up on another task invalidates sticky focus', () async {
    SharedPreferences.setMockInitialValues({});

    var movedImportance = 0;
    var movedUrgency = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'sticky', title: 'Roadmap', updatedAtMs: 50),
        todo(
          id: 'moved',
          title: 'Reply to client',
          updatedAtMs: 20,
          manualImportanceNudgeScore: movedImportance,
          manualUrgencyNudgeScore: movedUrgency,
        ),
      ],
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    movedImportance = 2;
    movedUrgency = 2;
    store.markDirty();
    await store.refresh();

    expect(store.snapshot.primaryFocus?.todo.id, 'moved');
  });

  test('manual move-down on the sticky task invalidates sticky focus',
      () async {
    SharedPreferences.setMockInitialValues({});

    var stickyImportance = 0;
    var stickyUrgency = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(
          id: 'sticky',
          title: 'Roadmap',
          updatedAtMs: 50,
          manualImportanceNudgeScore: stickyImportance,
          manualUrgencyNudgeScore: stickyUrgency,
        ),
        todo(id: 'other', title: 'Reply to client', updatedAtMs: 20),
      ],
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    stickyImportance = -2;
    stickyUrgency = -2;
    store.markDirty();
    await store.refresh();

    expect(store.snapshot.primaryFocus?.todo.id, 'other');
  });

  test('restoring ai order invalidates sticky focus for moved task', () async {
    SharedPreferences.setMockInitialValues({});

    var movedImportance = 0;
    var movedUrgency = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'sticky', title: 'Roadmap', updatedAtMs: 50),
        todo(
          id: 'moved',
          title: 'Reply to client',
          updatedAtMs: 20,
          manualImportanceNudgeScore: movedImportance,
          manualUrgencyNudgeScore: movedUrgency,
        ),
      ],
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    movedImportance = 2;
    movedUrgency = 2;
    store.markDirty();
    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'moved');

    movedImportance = 0;
    movedUrgency = 0;
    store.markDirty();
    await store.refresh();

    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');
  });
}
