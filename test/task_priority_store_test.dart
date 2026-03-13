import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  test('refresh publishes rules snapshot before async hybrid upgrade',
      () async {
    SharedPreferences.setMockInitialValues({});
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final snapshots = <TaskPrioritySnapshot>[];
    final completer = Completer<TaskPriorityAiBatchResult>();

    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => _FakeAiService(completer.future),
    );
    store.addListener(() => snapshots.add(store.snapshot));

    final refreshFuture = store.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
    expect(store.snapshot.decide.first.todo.id, 'focus');
    expect(store.isRefreshing, isTrue);

    completer.complete(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 20,
            reason: 'This is the obvious next step.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );
    await refreshFuture;

    expect(store.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(store.snapshot.primaryFocus?.todo.id, 'focus');
    expect(
        snapshots.map((entry) => entry.source),
        containsAll(<TaskPrioritySnapshotSource>[
          TaskPrioritySnapshotSource.rules,
          TaskPrioritySnapshotSource.hybrid,
        ]));
  });

  test('markDirty preserves snapshot but forces recompute', () async {
    SharedPreferences.setMockInitialValues({});
    var loadCount = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async {
        loadCount += 1;
        return <Todo>[todo(id: 't$loadCount', title: 'Task', updatedAtMs: 10)];
      },
    );

    await store.refresh();
    expect(store.snapshot.decide.first.todo.id, 't1');

    store.markDirty();
    await store.refresh();

    expect(store.snapshot.decide.first.todo.id, 't2');
    expect(loadCount, 2);
  });

  test('empty task list still yields an empty structured snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => const <Todo>[],
    );

    await store.refresh();

    expect(store.snapshot.isEmpty, isTrue);
    expect(store.snapshot.focus, isEmpty);
    expect(store.snapshot.scheduled, isEmpty);
    expect(store.snapshot.decide, isEmpty);
    expect(store.snapshot.done, isEmpty);
  });

  test('disabled task priority enhancement skips AI rerank', () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      isAiEnhancementEnabled: () async => false,
      resolveAiService: () async => aiService,
    );

    await store.refresh();

    expect(aiService.calls, 0);
    expect(store.aiAvailability, TaskPriorityAiAvailability.disabled);
    expect(store.isAiEnhancementAvailable, isFalse);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
  });

  test('reuses cached AI rerank while task signature stays unchanged',
      () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            priorityBand: TaskPriorityAiBand.focus,
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            suggestedAction: TaskPrioritySuggestionKind.doNow,
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => aiService,
    );

    await store.refresh();
    store.markDirty();
    await store.refresh();

    expect(aiService.calls, 1);
    expect(store.isAiEnhancementAvailable, isTrue);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.hybrid);
  });
}

final class _FakeAiService implements TaskPriorityAiService {
  _FakeAiService(this._future);

  final Future<TaskPriorityAiBatchResult> _future;

  @override
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request) {
    return _future;
  }
}

final class _CountingAiService implements TaskPriorityAiService {
  _CountingAiService(this._result);

  final TaskPriorityAiBatchResult _result;
  int calls = 0;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    calls += 1;
    return _result;
  }
}
