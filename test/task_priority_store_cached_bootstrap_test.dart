import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
      createdAtMs: 0,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  test(
      'persisted ai cache remains visible while a fresh rerank is still inflight',
      () async {
    final warmStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'cached', title: 'Keep cached task', updatedAtMs: 10),
        todo(id: 'fresh', title: 'Fresh task', updatedAtMs: 20),
      ],
      resolveAiService: () async => _ImmediateAiService(
        cacheScopeKey: 'bootstrap-cache',
        reason: 'Cached AI reason.',
      ),
    );

    await warmStore.refresh();
    expect(warmStore.snapshot.primaryFocus?.reasonText, 'Cached AI reason.');

    final release = Completer<void>();
    final delayedService = _DelayedAiService(
      cacheScopeKey: 'bootstrap-cache',
      release: release.future,
      reason: 'Fresh AI reason.',
    );
    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'cached', title: 'Keep cached task', updatedAtMs: 10),
        todo(id: 'fresh', title: 'Fresh task updated', updatedAtMs: 21),
      ],
      resolveAiService: () async => delayedService,
    );

    final refresh = secondStore.refresh();
    await _waitForNonIdleSnapshot(secondStore);

    expect(_reasonFor(secondStore, 'cached'), 'Cached AI reason.');
    expect(delayedService.requestTodoIds, <String>['fresh']);

    release.complete();
    await refresh;

    expect(secondStore.snapshot.primaryFocus?.reasonText, 'Fresh AI reason.');
  });
}

String? _reasonFor(TaskPriorityStore store, String todoId) {
  for (final entry in store.snapshot.activeEntries) {
    if (entry.todo.id == todoId) return entry.reasonText;
  }
  return null;
}

Future<void> _waitForNonIdleSnapshot(TaskPriorityStore store) async {
  for (var i = 0; i < 40; i += 1) {
    if (store.snapshot.computedAtLocal != null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('store snapshot never published');
}

final class _ImmediateAiService extends TaskPriorityAiService {
  _ImmediateAiService({
    required this.cacheScopeKey,
    required this.reason,
  });

  @override
  final String cacheScopeKey;
  final String reason;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: candidate.todoId == 'cached' ? 40 : 10,
              reason: reason,
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _DelayedAiService extends TaskPriorityAiService {
  _DelayedAiService({
    required this.cacheScopeKey,
    required this.release,
    required this.reason,
  });

  @override
  final String cacheScopeKey;
  final Future<void> release;
  final String reason;
  final List<String> requestTodoIds = <String>[];

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    requestTodoIds
        .addAll(request.candidates.map((candidate) => candidate.todoId));
    await release;
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: 80,
              reason: reason,
              confidence: TaskPriorityAiConfidence.high,
              isImportant: true,
              isUrgent: false,
            ),
          )
          .toList(growable: false),
    );
  }
}
