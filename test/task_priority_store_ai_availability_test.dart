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

  test('empty AI refresh resets snapshot back to current rules snapshot',
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
    expect(store.snapshot.source, TaskPrioritySnapshotSource.hybrid);
    expect(store.snapshot.primaryFocus?.reasonText, 'Available AI result.');

    title = 'Focus task updated';
    service = _EmptyScopedAiService(scopeKey: 'availability-cache');
    store.markDirty();
    await store.refresh();

    expect(store.aiAvailability, TaskPriorityAiAvailability.unavailable);
    expect(store.snapshot.source, TaskPrioritySnapshotSource.rules);
    expect(store.snapshot.hasAiEnhancement, isFalse);
    expect(
        store.snapshot.enhancementSource, TaskPriorityEnhancementSource.none);
    expect(store.snapshot.primaryFocus?.todo.title, 'Focus task updated');
    expect(store.snapshot.primaryFocus?.reasonText, isNull);
  });

  test('empty AI refresh clears bootstrap persisted snapshot fallback',
      () async {
    SharedPreferences.setMockInitialValues({});

    final warmStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );
    await warmStore.refresh();
    expect(warmStore.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task updated', updatedAtMs: 20),
      ],
      resolveAiService: () async => _EmptyScopedAiService(
        scopeKey: 'availability-cache',
      ),
    );

    await restartedStore.refresh();

    expect(
        restartedStore.aiAvailability, TaskPriorityAiAvailability.unavailable);
    expect(restartedStore.snapshot.source, TaskPrioritySnapshotSource.rules);
    expect(restartedStore.snapshot.hasAiEnhancement, isFalse);
    expect(
      restartedStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.none,
    );
    expect(
        restartedStore.snapshot.primaryFocus?.todo.title, 'Focus task updated');
    expect(restartedStore.snapshot.primaryFocus?.reasonText, isNull);
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

  test('newer local cache wins over older shared assessment', () async {
    SharedPreferences.setMockInitialValues({});
    final warmStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );

    await warmStore.refresh();
    expect(warmStore.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

    final nowLocal = DateTime(2026, 3, 13, 10, 6);
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

    final fallbackStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => 'availability-cache',
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async {
        return <String, TaskPriorityAiCachedAssessment>{
          'focus': TaskPriorityAiCachedAssessment(
            entry: const TaskPriorityAiEntry(
              todoId: 'focus',
              semanticAdjustment: 3,
              reason: 'Older shared assessment.',
              confidence: TaskPriorityAiConfidence.medium,
              isImportant: true,
              isUrgent: false,
            ),
            requestSignature: requestSignature,
            computedAtLocal: nowLocal.subtract(const Duration(minutes: 6)),
          ),
        };
      },
    );

    await fallbackStore.refresh();

    expect(
      fallbackStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(
      fallbackStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiLocalCache,
    );
  });

  test('restart fallback restores persisted AI result without resolved scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => null,
    );

    await restartedStore.refresh();

    expect(
      restartedStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(restartedStore.snapshot.hasAiEnhancement, isTrue);
    expect(restartedStore.shouldShowAiUpgradeHint, isFalse);
  });

  test(
      'restart fallback reuses the last persisted scope when multiple scopes match',
      () async {
    SharedPreferences.setMockInitialValues({});
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

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

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('task_priority_ai_cache_v3');
    final decoded = jsonDecode(raw!) as Map;
    final scopes = (decoded['scopes'] as Map)
        .map((key, value) => MapEntry(key.toString(), value));
    scopes['other-cache'] = <String, Object?>{
      'entries': <String, Object?>{
        'focus': <String, Object?>{
          'entry': const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 13,
            reason: 'Wrong scope result.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ).toJson(),
          'request_signature': requestSignature,
          'computed_at_ms':
              nowLocal.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
      },
    };
    await prefs.setString(
      'task_priority_ai_cache_v3',
      jsonEncode(<String, Object?>{
        ...decoded.map((key, value) => MapEntry(key.toString(), value)),
        'scopes': scopes,
      }),
    );

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal.add(const Duration(minutes: 5)),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => null,
    );

    await restartedStore.refresh();

    expect(
      restartedStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(restartedStore.snapshot.hasAiEnhancement, isTrue);
    expect(
      restartedStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiLocalCache,
    );
  });

  test(
      'restart fallback does not cross scopes when last persisted scope is missing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final nowLocal = DateTime(2026, 3, 13, 10, 0);
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _CachedSuccessfulAiService(),
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

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

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('task_priority_ai_cache_v3');
    final decoded = jsonDecode(raw!) as Map;
    final scopes = (decoded['scopes'] as Map)
        .map((key, value) => MapEntry(key.toString(), value));
    scopes['other-cache'] = <String, Object?>{
      'entries': <String, Object?>{
        'focus': <String, Object?>{
          'entry': const TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 13,
            reason: 'Wrong scope result.',
            confidence: TaskPriorityAiConfidence.high,
            isImportant: true,
            isUrgent: true,
          ).toJson(),
          'request_signature': requestSignature,
          'computed_at_ms':
              nowLocal.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
      },
    };
    await prefs.setString(
      'task_priority_ai_cache_v3',
      jsonEncode(<String, Object?>{
        ...decoded.map((key, value) => MapEntry(key.toString(), value)),
        'scopes': scopes,
        'last_scope': '',
      }),
    );

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal.add(const Duration(minutes: 5)),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => null,
    );

    await restartedStore.refresh();

    expect(restartedStore.snapshot.primaryFocus?.reasonText, isNull);
    expect(restartedStore.snapshot.hasAiEnhancement, isFalse);
    expect(
      restartedStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.none,
    );
  });

  test(
      'restart fallback ignores empty last scope and reuses older fresh persisted scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final nowLocal = DateTime(2026, 3, 13, 10, 0);

    final warmStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _ScopedCachedSuccessfulAiService(
        scopeKey: 'persisted-scope',
      ),
    );

    await warmStore.refresh();
    expect(warmStore.snapshot.primaryFocus?.reasonText, 'Persisted AI result.');

    final emptyScopeStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal.add(const Duration(minutes: 1)),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task updated', updatedAtMs: 20),
      ],
      resolveAiService: () async => _EmptyScopedAiService(
        scopeKey: 'empty-scope',
      ),
    );

    await emptyScopeStore.refresh();
    expect(emptyScopeStore.snapshot.primaryFocus?.reasonText, isNull);

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal.add(const Duration(minutes: 5)),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => null,
    );

    await restartedStore.refresh();

    expect(
      restartedStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(restartedStore.snapshot.hasAiEnhancement, isTrue);
    expect(
      restartedStore.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiLocalCache,
    );
  });

  test(
      'refresh keeps previously fresh persisted scope when write happens after TTL boundary',
      () async {
    SharedPreferences.setMockInitialValues({});
    final startNow = DateTime(2026, 3, 13, 10, 0);
    const ttl = Duration(minutes: 5);

    var currentNow = startNow;
    final warmStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => currentNow,
      aiCacheTtl: ttl,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => _ScopedCachedSuccessfulAiService(
        scopeKey: 'persisted-scope',
      ),
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        currentNow = startNow.add(const Duration(minutes: 6));
      },
    );

    await warmStore.refresh();

    final restartedStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => startNow.add(const Duration(minutes: 4, seconds: 30)),
      aiCacheTtl: ttl,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Focus task', updatedAtMs: 10),
      ],
      resolveAiService: () async => null,
      resolveAiCacheScopeKey: () async => null,
    );

    await restartedStore.refresh();

    expect(
      restartedStore.snapshot.primaryFocus?.reasonText,
      'Persisted AI result.',
    );
    expect(restartedStore.snapshot.hasAiEnhancement, isTrue);
    expect(
      restartedStore.snapshot.enhancementSource,
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

final class _ScopedCachedSuccessfulAiService extends TaskPriorityAiService {
  _ScopedCachedSuccessfulAiService({required this.scopeKey});

  final String scopeKey;

  @override
  String get cacheScopeKey => scopeKey;

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

final class _EmptyScopedAiService extends TaskPriorityAiService {
  _EmptyScopedAiService({required this.scopeKey});

  final String scopeKey;

  @override
  String get cacheScopeKey => scopeKey;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    return const TaskPriorityAiBatchResult.empty();
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
