import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
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

  test('sticky focus survives pure semantic score drift on another task',
      () async {
    SharedPreferences.setMockInitialValues({});

    var secondPass = false;
    var changedTitle = 'Task B';
    final service = _SemanticScoreDriftAiService(() => secondPass);
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

    secondPass = true;
    changedTitle = 'Task B refreshed';
    store.markDirty();
    await store.refresh();

    expect(service.calls, 2);
    expect(store.snapshot.primaryFocus?.todo.id, 'sticky');
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
}

final class _CountingAiService extends TaskPriorityAiService {
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

final class _StickyAwareAiService extends TaskPriorityAiService {
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

final class _SemanticStickyInvalidationAiService extends TaskPriorityAiService {
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

final class _SemanticScoreDriftAiService extends TaskPriorityAiService {
  _SemanticScoreDriftAiService(this._secondPass);

  final bool Function() _secondPass;

  @override
  String get cacheScopeKey => 'semantic-score-drift';

  int calls = 0;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    calls += 1;
    final otherScore = _secondPass() ? 18.0 : 8.0;
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment:
                  candidate.todoId == 'sticky' ? 12.0 : otherScore,
              reason: candidate.todoId == 'sticky'
                  ? 'Keep this visible.'
                  : 'Same task, slightly different score.',
              confidence: TaskPriorityAiConfidence.medium,
              isImportant: false,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}
