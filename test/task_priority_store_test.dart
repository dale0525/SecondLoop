import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  setUp(() {
    BackendTaskPriorityAiService.clearSharedCacheForTest();
  });

  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
    int? reviewStage,
    int? nextReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
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
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
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
            semanticAdjustment: 20,
            reason: 'This is the obvious next step.',
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

  test('transient checklist progress load failure preserves prior data',
      () async {
    SharedPreferences.setMockInitialValues({});
    var progressCalls = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      loadChecklistProgress: () async {
        progressCalls += 1;
        if (progressCalls == 1) {
          return const <TodoChecklistProgress>[
            TodoChecklistProgress(todoId: 'focus', doneCount: 1, totalCount: 2),
          ];
        }
        throw StateError('transient checklist progress failure');
      },
    );

    await store.refresh();
    expect(
        store.checklistProgressByTodoId['focus'],
        const TodoChecklistProgress(
            todoId: 'focus', doneCount: 1, totalCount: 2));

    store.markDirty();
    await store.refresh();

    expect(
        store.checklistProgressByTodoId['focus'],
        const TodoChecklistProgress(
            todoId: 'focus', doneCount: 1, totalCount: 2));
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

  test('refresh clears refreshing state when early load throws', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => throw StateError('load failed'),
    );

    await expectLater(store.refresh(), throwsStateError);

    expect(store.isRefreshing, isFalse);
  });

  test('refresh does not notify after dispose while inflight completes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final completer = Completer<List<Todo>>();
    var notifyCount = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () => completer.future,
    );
    store.addListener(() => notifyCount += 1);

    final refreshFuture = store.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(store.isRefreshing, isTrue);

    store.dispose();
    completer.complete(<Todo>[todo(id: 't1', title: 'Task', updatedAtMs: 10)]);

    await expectLater(refreshFuture, completes);
    expect(notifyCount, 1);
  });

  test('force refresh after dispose does not reuse disposed store', () async {
    SharedPreferences.setMockInitialValues({});
    final completer = Completer<List<Todo>>();
    var notifyCount = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () => completer.future,
    );
    store.addListener(() => notifyCount += 1);

    final firstRefresh = store.refresh();
    await Future<void>.delayed(Duration.zero);
    final forcedRefresh = store.refresh(force: true);
    store.dispose();
    completer.complete(<Todo>[todo(id: 't1', title: 'Task', updatedAtMs: 10)]);

    await expectLater(firstRefresh, completes);
    await expectLater(forcedRefresh, completes);
    expect(notifyCount, 1);
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
            semanticAdjustment: 20,
            reason: 'Still the best option.',
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

  test('force refresh waits for inflight refresh then recomputes', () async {
    SharedPreferences.setMockInitialValues({});
    var loadCount = 0;
    final completer = Completer<void>();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async {
        loadCount += 1;
        if (loadCount == 1) {
          await completer.future;
        }
        return <Todo>[todo(id: 't$loadCount', title: 'Task', updatedAtMs: 10)];
      },
    );

    final firstRefresh = store.refresh();
    await Future<void>.delayed(Duration.zero);
    final forcedRefresh = store.refresh(force: true);
    completer.complete();

    await Future.wait(<Future<void>>[firstRefresh, forcedRefresh]);

    expect(loadCount, 2);
    expect(store.snapshot.decide.first.todo.id, 't2');
  });

  test('reuses cached AI rerank while task signature stays unchanged',
      () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Still the best option.',
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

  test('future-dated in-memory AI cache is treated as stale', () async {
    SharedPreferences.setMockInitialValues({});
    var currentNow = DateTime(2026, 3, 13, 10, 20);
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Handle it now.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => currentNow,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => aiService,
    );

    await store.refresh();
    currentNow = DateTime(2026, 3, 13, 10, 0);
    store.markDirty();
    await store.refresh();

    expect(aiService.calls, 2);
  });

  test('future-dated persisted AI cache is treated as stale', () async {
    SharedPreferences.setMockInitialValues({});
    final firstService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Future cache result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final firstStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 20),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => firstService,
    );

    await firstStore.refresh();

    final secondService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Fresh rerank result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => secondService,
    );

    await secondStore.refresh();

    expect(secondService.calls, 1);
    expect(
        secondStore.snapshot.primaryFocus?.reasonText, 'Fresh rerank result.');
  });

  test('reuses persisted AI rerank across store recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final firstService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final firstStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => firstService,
    );

    await firstStore.refresh();

    final secondService = _CountingAiService(
      const TaskPriorityAiBatchResult.empty(),
      cacheScopeKey: 'byok|model|en-US',
    );
    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => secondService,
    );

    await secondStore.refresh();

    expect(firstService.calls, 1);
    expect(secondService.calls, 0);
    expect(secondStore.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(secondStore.snapshot.primaryFocus?.reasonText,
        'Still the best option.');
  });

  test('uses persisted AI rerank when ai service is unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    final firstService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final firstStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => firstService,
    );

    await firstStore.refresh();

    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => 'byok|model|en-US',
    );

    await secondStore.refresh();

    expect(secondStore.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(secondStore.snapshot.primaryFocus?.reasonText,
        'Still the best option.');
    expect(secondStore.isAiEnhancementAvailable, isFalse);
    expect(
      secondStore.aiAvailability,
      TaskPriorityAiAvailability.unavailable,
    );
  });

  test(
      'does not reuse persisted AI rerank when unavailable cache scope differs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final firstService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final firstStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => firstService,
    );

    await firstStore.refresh();

    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => 'byok|other-model|en-US',
    );

    await secondStore.refresh();

    expect(secondStore.snapshot.source, TaskPrioritySnapshotSource.rules);
    expect(secondStore.snapshot.primaryFocus?.reasonText, isNull);
  });

  test(
      'separator-like fields do not collide in persisted AI request signatures',
      () async {
    SharedPreferences.setMockInitialValues({});
    final firstService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'a:b',
            semanticAdjustment: 20,
            reason: 'First tuple result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final firstStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'a:b', title: 'Task A', status: 'c', updatedAtMs: 10),
      ],
      resolveAiService: () async => firstService,
    );

    await firstStore.refresh();

    final secondService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'a',
            semanticAdjustment: 20,
            reason: 'Second tuple result.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'a', title: 'Task B', status: 'b:c', updatedAtMs: 10),
      ],
      resolveAiService: () async => secondService,
    );

    await secondStore.refresh();

    expect(firstService.calls, 1);
    expect(secondService.calls, 1);
    expect(secondStore.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(
        secondStore.snapshot.primaryFocus?.reasonText, 'Second tuple result.');
  });

  test('updatedAtMs churn alone does not trigger a second rerank', () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Still the best option.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
    );
    var updatedAtMs = 10;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: updatedAtMs),
      ],
      resolveAiService: () async => aiService,
    );

    await store.refresh();
    updatedAtMs = 999;
    store.markDirty();
    await store.refresh();

    expect(aiService.calls, 1);
  });

  test('due state changes bypass sticky focus and recompute primary focus',
      () async {
    SharedPreferences.setMockInitialValues({});

    var nowLocal = DateTime(2026, 3, 13, 10, 0);
    final reviewAt = DateTime(2026, 3, 15, 11, 0);
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(
          id: 'sticky',
          title: 'Roadmap',
          updatedAtMs: 50,
          manualUrgencyNudgeScore: 1,
        ),
        todo(
          id: 'review',
          title: 'Reply to client',
          updatedAtMs: 20,
          dueAtMs: reviewAt.toUtc().millisecondsSinceEpoch,
        ),
      ],
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    nowLocal = DateTime(2026, 3, 15, 12, 0);
    store.markDirty();
    await store.refresh();

    expect(store.snapshot.primaryFocus?.todo.id, 'review');
  });

  test('manual urgency change on another task invalidates sticky focus',
      () async {
    SharedPreferences.setMockInitialValues({});

    var reviewUrgency = 0;
    var reviewImportance = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(
          id: 'sticky',
          title: 'Roadmap',
          updatedAtMs: 50,
          manualUrgencyNudgeScore: 1,
        ),
        todo(
          id: 'review',
          title: 'Reply to client',
          updatedAtMs: 20,
          manualUrgencyNudgeScore: reviewUrgency,
          manualImportanceNudgeScore: reviewImportance,
        ),
      ],
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    reviewUrgency = 1;
    reviewImportance = 1;
    store.markDirty();
    await store.refresh();

    expect(store.snapshot.primaryFocus?.todo.id, 'review');
  });

  test('sticky focus survives unrelated rerank changes on other tasks',
      () async {
    SharedPreferences.setMockInitialValues({});

    var changedTitle = 'Task B';
    final service = _StickyAwareAiService();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'sticky', title: 'Roadmap', updatedAtMs: 100),
        todo(id: 'other', title: changedTitle, updatedAtMs: 10),
      ],
      resolveAiService: () async => service,
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    changedTitle = 'Task B updated';
    store.markDirty();
    await store.refresh();

    expect(service.calls, 2);
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');
  });

  test('sticky focus yields when semantic priority changes on another task',
      () async {
    SharedPreferences.setMockInitialValues({});

    var changedTitle = 'Task B';
    final service = _SemanticStickyInvalidationAiService();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'sticky', title: 'Roadmap', updatedAtMs: 100),
        todo(id: 'other', title: changedTitle, updatedAtMs: 10),
      ],
      resolveAiService: () async => service,
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');

    changedTitle = 'Task B updated';
    store.markDirty();
    await store.refresh();

    expect(service.calls, 2);
    expect(store.snapshot.primaryFocus?.todo.id, 'other');
  });

  test('ai rerank still runs when cache scope key is empty', () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Fresh AI result without persisted cache.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ),
        ],
      ),
      cacheScopeKey: '',
    );
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => aiService,
    );

    await store.refresh();

    expect(aiService.calls, 1);
    expect(
      store.snapshot.primaryFocus?.reasonText,
      'Fresh AI result without persisted cache.',
    );
  });

  test('empty cache scope reuses in-memory ai assessments across refreshes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 18,
            reason: 'Fresh AI result without persisted cache.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ),
        ],
      ),
      cacheScopeKey: '',
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
    expect(
      store.snapshot.primaryFocus?.reasonText,
      'Fresh AI result without persisted cache.',
    );
  });

  test(
      'manual nudge fields on todos survive store reload without local signal store',
      () async {
    SharedPreferences.setMockInitialValues({});
    TaskPriorityStore buildStore() {
      return TaskPriorityStore.fromLoaders(
        nowLocal: () => DateTime(2026, 3, 20, 10, 0),
        loadTodos: () async => <Todo>[
          todo(
            id: 'focus',
            title: 'Synced nudge task',
            updatedAtMs: 10,
            manualUrgencyNudgeScore: 1,
            manualImportanceNudgeScore: -1,
          ),
        ],
      );
    }

    final firstStore = buildStore();
    await firstStore.refresh();
    expect(firstStore.snapshot.primaryFocus?.manualUrgencyNudgeScore, 1);
    expect(firstStore.snapshot.primaryFocus?.manualImportanceNudgeScore, -1);

    final secondStore = buildStore();
    await secondStore.refresh();
    expect(secondStore.snapshot.primaryFocus?.manualUrgencyNudgeScore, 1);
    expect(secondStore.snapshot.primaryFocus?.manualImportanceNudgeScore, -1);
  });

  test('changing ai cache scope triggers a fresh rerank', () async {
    SharedPreferences.setMockInitialValues({});
    final englishService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: 'Handle it now.',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|en-US',
    );
    final chineseService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 20,
            reason: '现在处理。',
            confidence: TaskPriorityAiConfidence.high,
          ),
        ],
      ),
      cacheScopeKey: 'byok|model|zh-CN',
    );
    var currentService = englishService;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => currentService,
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.reasonText, 'Handle it now.');

    currentService = chineseService;
    store.markDirty();
    await store.refresh();

    expect(englishService.calls, 1);
    expect(chineseService.calls, 1);
    expect(store.snapshot.primaryFocus?.reasonText, '现在处理。');
  });
  test('ai enhancement is not considered enabled before availability resolves',
      () {
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => const <Todo>[],
    );

    expect(store.aiAvailability, TaskPriorityAiAvailability.unknown);
    expect(store.isAiEnhancementEnabled, isFalse);
  });
}

final class _FakeAiService implements TaskPriorityAiService {
  _FakeAiService(this._future);

  @override
  String get cacheScopeKey => 'fake';

  final Future<TaskPriorityAiBatchResult> _future;

  @override
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request) {
    return _future;
  }
}

final class _CountingAiService implements TaskPriorityAiService {
  _CountingAiService(this._result, {this.cacheScopeKey = 'counting'});

  final TaskPriorityAiBatchResult _result;
  @override
  final String cacheScopeKey;
  int calls = 0;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    calls += 1;
    return _result;
  }
}

final class _StickyAwareAiService implements TaskPriorityAiService {
  @override
  String get cacheScopeKey => 'sticky-aware';

  int calls = 0;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    calls += 1;
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: candidate.todoId == 'sticky' ? 12 : 5,
              reason: candidate.todoId == 'sticky'
                  ? 'Keep this visible.'
                  : 'Refreshed candidate context.',
              confidence: TaskPriorityAiConfidence.medium,
              isImportant: candidate.todoId == 'sticky',
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _SemanticStickyInvalidationAiService
    implements TaskPriorityAiService {
  @override
  String get cacheScopeKey => 'semantic-sticky';

  int calls = 0;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    calls += 1;
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: candidate.title.contains('updated') ? 40 : 0,
              reason: candidate.title.contains('updated')
                  ? 'This just became more important.'
                  : 'Keep this visible.',
              confidence: TaskPriorityAiConfidence.medium,
              isImportant: false,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}
