import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_signal_store.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  setUp(() {
    TaskPrioritySignalStore.resetMutationQueueForTest();
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
}

final class _SuccessfulAiService implements TaskPriorityAiService {
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

final class _FailingAiService implements TaskPriorityAiService {
  const _FailingAiService();

  @override
  String get cacheScopeKey => '';

  @override
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request) {
    throw StateError('AI unavailable');
  }
}
