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
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => _ImmediateAiService(
        cacheScopeKey: 'bootstrap-cache',
        reason: 'Cached AI reason.',
      ),
    );

    await warmStore.refresh();
    expect(warmStore.snapshot.primaryFocus?.reasonText, 'Cached AI reason.');

    final release = Completer<void>();
    final secondStore = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 5),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => _DelayedAiService(
        cacheScopeKey: 'bootstrap-cache',
        release: release.future,
        reason: 'Fresh AI reason.',
      ),
    );

    final refresh = secondStore.refresh();
    await _waitForNonIdleSnapshot(secondStore);

    expect(secondStore.snapshot.primaryFocus?.reasonText, 'Cached AI reason.');

    release.complete();
    await refresh;

    expect(secondStore.snapshot.primaryFocus?.reasonText, 'Cached AI reason.');
  });
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
              semanticAdjustment: 20,
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

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    await release;
    return TaskPriorityAiBatchResult(
      entries: request.candidates
          .map(
            (candidate) => TaskPriorityAiEntry(
              todoId: candidate.todoId,
              semanticAdjustment: 22,
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
