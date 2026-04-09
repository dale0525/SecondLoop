import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_feedback_store.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BackendTaskPriorityAiService.clearSharedCacheForTest();
  });

  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
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
    );
  }

  test('refresh publishes local snapshot before delayed ai result', () async {
    final aiRelease = Completer<void>();
    final localPublished = Completer<void>();
    final published = <TaskPrioritySnapshot>[];
    late final TaskPriorityStore store;
    store = TaskPriorityStore.fromLoaders(
      loadTodos: () async => <Todo>[
        todo(id: 'a', title: 'Alpha task', updatedAtMs: 20),
        todo(id: 'b', title: 'Beta task', updatedAtMs: 10),
      ],
      nowLocal: () => DateTime(2026, 4, 7, 12),
      resolveAiService: () async => _DelayedAiService(
        release: aiRelease.future,
        result: const TaskPriorityAiBatchResult(
          entries: <TaskPriorityAiEntry>[
            TaskPriorityAiEntry(
              todoId: 'b',
              semanticAdjustment: 30,
              reason: 'AI promotes B',
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: true,
            ),
          ],
        ),
      ),
    )..addListener(() {
        final snapshot = store.snapshot;
        if (snapshot.computedAtLocal == null) return;
        published.add(snapshot);
        if (snapshot.resolutionPhase ==
                TaskPriorityResolutionPhase.awaitingAi &&
            !localPublished.isCompleted) {
          localPublished.complete();
        }
      });

    final refreshFuture = store.refresh(force: true);

    await localPublished.future;

    expect(
        published.last.resolutionPhase, TaskPriorityResolutionPhase.awaitingAi);
    expect(published.last.primaryFocus?.todo.id, 'a');

    aiRelease.complete();
    await refreshFuture;

    expect(
        store.snapshot.resolutionPhase, TaskPriorityResolutionPhase.aiResolved);
    expect(store.snapshot.primaryFocus?.todo.id, 'b');
  });

  test('ai failure leaves store on local fallback phase', () async {
    final store = TaskPriorityStore.fromLoaders(
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fallback task', updatedAtMs: 10),
      ],
      nowLocal: () => DateTime(2026, 4, 7, 12),
      resolveAiService: () async => const _FailingAiService(),
    );

    await store.refresh(force: true);

    expect(
      store.snapshot.resolutionPhase,
      TaskPriorityResolutionPhase.localFallback,
    );
    expect(
      store.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.none,
    );
    expect(store.snapshot.primaryFocus?.todo.id, 'focus');
  });

  test(
      'forced refresh publishes local snapshot before inflight resolver finishes',
      () async {
    final firstAiRelease = Completer<void>();
    final secondLocalPublished = Completer<void>();
    final published = <TaskPrioritySnapshot>[];
    var checklistProgressCallCount = 0;
    var resolveCallCount = 0;
    final feedbackStore = _TrackingFeedbackStore();

    late final TaskPriorityStore store;
    store = TaskPriorityStore.fromLoaders(
      loadTodos: () async => <Todo>[
        todo(id: 'a', title: 'Alpha task', updatedAtMs: 20),
        todo(id: 'b', title: 'Beta task', updatedAtMs: 10),
      ],
      loadChecklistProgress: () async {
        checklistProgressCallCount += 1;
        return <TodoChecklistProgress>[
          TodoChecklistProgress(
            todoId: 'a',
            doneCount: checklistProgressCallCount,
            totalCount: 3,
          ),
        ];
      },
      nowLocal: () => DateTime(2026, 4, 7, 12),
      feedbackStore: feedbackStore,
      resolveAiService: () async {
        resolveCallCount += 1;
        if (resolveCallCount == 1) {
          return _DelayedAiService(
            release: firstAiRelease.future,
            result: const TaskPriorityAiBatchResult(
                entries: <TaskPriorityAiEntry>[]),
          );
        }
        return const _FailingAiService();
      },
    )..addListener(() {
        final snapshot = store.snapshot;
        if (snapshot.computedAtLocal == null) return;
        published.add(snapshot);
        if (snapshot.refreshGeneration == 2 &&
            snapshot.resolutionPhase ==
                TaskPriorityResolutionPhase.awaitingAi &&
            !secondLocalPublished.isCompleted) {
          secondLocalPublished.complete();
        }
      });

    final firstRefresh = store.refresh(force: true);
    await Future<void>.microtask(() {});
    await Future<void>.microtask(() {});

    final forcedRefresh = store.refresh(force: true);

    await expectLater(
      secondLocalPublished.future.timeout(const Duration(milliseconds: 100)),
      completes,
    );

    expect(store.checklistProgressByTodoId['a']?.doneCount, 1);
    expect(feedbackStore.pruneCallCount, 1);
    expect(resolveCallCount, 1);

    firstAiRelease.complete();
    await forcedRefresh;
    await firstRefresh;

    expect(
      published.any(
        (snapshot) =>
            snapshot.refreshGeneration == 2 &&
            snapshot.resolutionPhase == TaskPriorityResolutionPhase.awaitingAi,
      ),
      isTrue,
    );
    expect(store.checklistProgressByTodoId['a']?.doneCount, 2);
    expect(feedbackStore.pruneCallCount, 2);
    expect(resolveCallCount, 2);
  });
}

final class _DelayedAiService extends TaskPriorityAiService {
  _DelayedAiService({required this.release, required this.result});

  final Future<void> release;
  final TaskPriorityAiBatchResult result;

  @override
  String get cacheScopeKey => 'delayed-ai';

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    await release;
    return result;
  }
}

final class _FailingAiService extends TaskPriorityAiService {
  const _FailingAiService();

  @override
  String get cacheScopeKey => 'failing-ai';

  @override
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request) {
    throw StateError('AI unavailable');
  }
}

final class _TrackingFeedbackStore extends TaskPriorityFeedbackStore {
  int pruneCallCount = 0;

  @override
  Future<void> pruneToTodoIds(Iterable<String> todoIds) async {
    pruneCallCount += 1;
    await super.pruneToTodoIds(todoIds);
  }
}
