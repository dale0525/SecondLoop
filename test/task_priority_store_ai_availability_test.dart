import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
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

  test('free tier keeps base priority and shows upgrade hint state', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Free tier focus', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
    );

    await store.refresh();

    expect(store.isBasePriorityAvailable, isTrue);
    expect(store.aiAvailability, TaskPriorityAiAvailability.unavailable);
    expect(store.isAiEnhancementAvailable, isFalse);
    expect(store.shouldShowAiUpgradeHint, isTrue);
    expect(store.baseSnapshot.primaryFocus?.todo.id, 'focus');
    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
  });

  test('disabled enhancement keeps base priority without upgrade hint',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Disabled focus', updatedAtMs: 10),
      ],
      isAiEnhancementEnabled: () async => false,
    );

    await store.refresh();

    expect(store.isBasePriorityAvailable, isTrue);
    expect(store.aiAvailability, TaskPriorityAiAvailability.disabled);
    expect(store.isAiEnhancementAvailable, isFalse);
    expect(store.shouldShowAiUpgradeHint, isFalse);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
  });

  test('available enhancement keeps base snapshot alongside hybrid result',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Pro focus', updatedAtMs: 10),
      ],
      resolveAiService: () async => _SuccessfulAiService(),
    );

    await store.refresh();

    expect(store.isBasePriorityAvailable, isTrue);
    expect(store.isAiEnhancementAvailable, isTrue);
    expect(store.shouldShowAiUpgradeHint, isFalse);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(store.baseSnapshot.source, TaskPrioritySnapshotSource.rules);
    expect(store.snapshot.hasAiEnhancement, isTrue);
  });

  test('availability falls back when refresh yields no AI assessments',
      () async {
    SharedPreferences.setMockInitialValues({});
    var title = 'Focus task';
    TaskPriorityAiService service = _SuccessfulAiService();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: title, updatedAtMs: 10),
      ],
      resolveAiService: () async => service,
    );

    await store.refresh();
    expect(store.isAiEnhancementAvailable, isTrue);

    title = 'Focus task updated';
    service = const _FailingAiService();
    store.markDirty();
    await store.refresh();

    expect(store.isAiEnhancementAvailable, isFalse);
    expect(store.aiAvailability, TaskPriorityAiAvailability.unavailable);
  });

  test('unavailable AI still keeps base priority snapshot usable', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => const _FailingAiService(),
    );

    await store.refresh();

    expect(store.aiAvailability, TaskPriorityAiAvailability.unavailable);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
    expect(store.snapshot.primaryFocus?.todo.id, 'focus');
    expect(store.snapshot.basePrimaryFocus?.todo.id, 'focus');
    expect(store.baseSnapshot.primaryFocus?.todo.id, 'focus');
    expect(store.snapshot.hasAiEnhancement, isFalse);
  });

  test(
      'shared assessment fallback reuses remote enhancement before local rerank',
      () async {
    SharedPreferences.setMockInitialValues({});
    var remoteReads = 0;
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final requestSignature = jsonEncode(<String, Object?>{
      'time_bucket': buildTaskPriorityAiTimeBucket(nowLocal),
      'candidate': buildTaskPriorityAiRequest(
        buildTaskPrioritySnapshot(
          <Todo>[todo(id: 'focus', title: 'Focus task', updatedAtMs: 10)],
          nowLocal: nowLocal,
        ),
        nowLocal: nowLocal,
      ).candidates.single.toJson(),
    });
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => 'shared-cache',
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async {
        remoteReads += 1;
        return <String, TaskPriorityAiCachedAssessment>{
          'focus': TaskPriorityAiCachedAssessment(
            entry: const TaskPriorityAiEntry(
              todoId: 'focus',
              semanticAdjustment: 18,
              reason: 'Shared assessment result.',
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: true,
            ),
            requestSignature: requestSignature,
            computedAtLocal: nowLocal,
          ),
        };
      },
    );

    await store.refresh();

    expect(remoteReads, 1);
    expect(store.aiAvailability, TaskPriorityAiAvailability.unavailable);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(
        store.snapshot.primaryFocus?.reasonText, 'Shared assessment result.');
    expect(store.isAiEnhancementAvailable, isFalse);
    expect(
      store.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiSharedCache,
    );
  });

  test('persisted AI fallback does not mark live AI as available', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );

    await store.refresh();
    expect(store.isAiEnhancementAvailable, isTrue);
    expect(store.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

    final fallbackStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => 'availability-cache',
    );

    await fallbackStore.refresh();

    expect(fallbackStore.isAiEnhancementAvailable, isFalse);
    expect(
      fallbackStore.aiAvailability,
      TaskPriorityAiAvailability.unavailable,
    );
    expect(
      fallbackStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(fallbackStore.shouldShowAiUpgradeHint, isFalse);
    expect(fallbackStore.snapshot.hasAiEnhancement, isTrue);
    expect(
      fallbackStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiLocalCache,
    );
  });

  test('fresh rerank marks enhancement source as live ai', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _SuccessfulAiService(),
    );

    await store.refresh();

    expect(store.snapshot.hasAiEnhancement, isTrue);
    expect(
      store.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiLive,
    );
  });
}

final class _SuccessfulAiService extends TaskPriorityAiService {
  @override
  String get cacheScopeKey => '';

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: 8,
              reason: 'Available AI result.',
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _CachedSuccessfulAiService extends TaskPriorityAiService {
  @override
  String get cacheScopeKey => 'availability-cache';

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: 8,
              reason: 'Persisted AI result.',
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _FailingAiService extends TaskPriorityAiService {
  const _FailingAiService();

  @override
  String get cacheScopeKey => '';

  @override
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request) {
    throw StateError('AI unavailable');
  }
}
