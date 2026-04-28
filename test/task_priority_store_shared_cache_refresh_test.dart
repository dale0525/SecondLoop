import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_models.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_store.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('complete local AI cache skips immediate redundant shared cache I/O',
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
      cacheScopeKey: 'cloud-scope',
    );
    var sharedReadCalls = 0;
    var sharedWriteCalls = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => aiService,
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async {
        sharedReadCalls += 1;
        return const <String, TaskPriorityAiCachedAssessment>{};
      },
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        sharedWriteCalls += 1;
      },
    );

    await store.refresh();
    store.markDirty();
    await store.refresh();

    expect(aiService.calls, 1);
    expect(sharedReadCalls, 1);
    expect(sharedWriteCalls, 1);
  });

  test('complete local AI cache periodically merges newer shared cache',
      () async {
    SharedPreferences.setMockInitialValues({});
    final localAiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'focus',
            semanticAdjustment: 8,
            reason: 'Local cached result.',
            confidence: TaskPriorityAiConfidence.medium,
          ),
        ],
      ),
      cacheScopeKey: 'cloud-scope',
    );
    var nowLocal = DateTime(2026, 3, 13, 10, 0);
    var sharedReadCalls = 0;
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => nowLocal,
      loadTodos: () async => <Todo>[
        todo(id: 'focus', title: 'Fix prod bug', updatedAtMs: 10),
      ],
      resolveAiService: () async => localAiService,
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async {
        sharedReadCalls += 1;
        if (sharedReadCalls == 1) {
          return const <String, TaskPriorityAiCachedAssessment>{};
        }
        final signature = await _persistedRequestSignatureFor(
          cacheScopeKey: cacheScopeKey,
          todoId: 'focus',
        );
        return <String, TaskPriorityAiCachedAssessment>{
          'focus': TaskPriorityAiCachedAssessment(
            entry: const TaskPriorityAiEntry(
              todoId: 'focus',
              semanticAdjustment: 24,
              reason: 'Newer shared result.',
              confidence: TaskPriorityAiConfidence.high,
            ),
            requestSignature: signature,
            computedAtLocal: nowLocal,
          ),
        };
      },
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {},
    );

    await store.refresh();
    expect(store.snapshot.primaryFocus?.reasonText, 'Local cached result.');

    nowLocal = nowLocal.add(const Duration(minutes: 2));
    store.markDirty();
    await store.refresh();

    expect(localAiService.calls, 1);
    expect(sharedReadCalls, 2);
    expect(store.snapshot.primaryFocus?.reasonText, 'Newer shared result.');
    expect(
      store.snapshot.enhancementSource,
      TaskPriorityEnhancementSource.aiSharedCache,
    );
  });

  test('cache-only refresh writes shared cache when active todos shrink',
      () async {
    SharedPreferences.setMockInitialValues({});
    final aiService = _CountingAiService(
      const TaskPriorityAiBatchResult(
        entries: <TaskPriorityAiEntry>[
          TaskPriorityAiEntry(
            todoId: 'a',
            semanticAdjustment: 8,
            reason: 'Task A result.',
            confidence: TaskPriorityAiConfidence.medium,
          ),
          TaskPriorityAiEntry(
            todoId: 'b',
            semanticAdjustment: 6,
            reason: 'Task B result.',
            confidence: TaskPriorityAiConfidence.medium,
          ),
        ],
      ),
      cacheScopeKey: 'cloud-scope',
    );
    var todoIds = <String>['a', 'b'];
    final sharedWriteActiveIds = <Set<String>>[];
    final store = TaskPriorityStore.fromLoaders(
      nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      loadTodos: () async => todoIds
          .map(
            (id) => todo(
              id: id,
              title: 'Task ${id.toUpperCase()}',
              updatedAtMs: id == 'a' ? 10 : 20,
            ),
          )
          .toList(growable: false),
      resolveAiService: () async => aiService,
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async {
        return const <String, TaskPriorityAiCachedAssessment>{};
      },
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        sharedWriteActiveIds.add(activeTodoIds.map((id) => id.trim()).toSet());
      },
    );

    await store.refresh();
    todoIds = <String>['a'];
    store.markDirty();
    await store.refresh();

    expect(aiService.calls, 1);
    expect(sharedWriteActiveIds, hasLength(2));
    expect(sharedWriteActiveIds.last, <String>{'a'});
  });
}

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

Future<String> _persistedRequestSignatureFor({
  required String cacheScopeKey,
  required String todoId,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('task_priority_ai_cache_v3');
  final decoded = jsonDecode(raw!) as Map;
  final scopes = decoded['scopes'] as Map;
  final scope = scopes[cacheScopeKey] as Map;
  final entries = scope['entries'] as Map;
  final entry = entries[todoId] as Map;
  return entry['request_signature'] as String;
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
