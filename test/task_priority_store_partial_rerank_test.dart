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

  test('candidate context changes trigger a full rerank', () async {
    SharedPreferences.setMockInitialValues({});
    var changedTitle = 'Task B';
    final service = _RecordingAiService();
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'a', title: 'Task A', updatedAtMs: 10),
        todo(id: 'b', title: changedTitle, updatedAtMs: 20),
      ],
      resolveAiService: () async => service,
    );

    await store.refresh();
    expect(service.requestSizes, <int>[2]);

    changedTitle = 'Task B updated';
    store.markDirty();
    await store.refresh();

    expect(service.requestSizes, <int>[2, 2]);
  });
}

final class _RecordingAiService implements TaskPriorityAiService {
  @override
  String get cacheScopeKey => 'test-scope';

  final List<int> requestSizes = <int>[];

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    requestSizes.add(request.candidates.length);
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              priorityBand: TaskPriorityAiBand.next,
              semanticAdjustment: 5,
              reason: 'cached',
              suggestedAction: TaskPrioritySuggestionKind.schedule,
              confidence: TaskPriorityAiConfidence.medium,
              isImportant: candidate.todoId == 'a',
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}
