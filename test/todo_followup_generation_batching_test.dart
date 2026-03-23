import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_followup_generation_gate.dart';
import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('preview selection reserves one auto slot for mixed backlog', () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 6; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
      const TodoFollowupGenerationJob(
        todoId: 'todo_auto_1',
        triggerKind: 'auto_create',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 10,
      ),
    ];

    final selected = selectTodoFollowupGenerationPreviewJobs(
      previewJobs,
      batchLimit: 5,
    );

    expect(selected, hasLength(5));
    expect(
      selected.where((job) => job.triggerKind == 'manual_regenerate'),
      hasLength(4),
    );
    expect(selected.any((job) => job.todoId == 'todo_auto_1'), isTrue);
  });

  test('preview refetch triggers when the initial batch is all manual', () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 5; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
    ];

    expect(
      shouldRefetchTodoFollowupGenerationPreviewJobs(
        previewJobs,
        batchLimit: 5,
      ),
      isTrue,
    );
  });

  test('generation passes keep one auto slot when manual jobs fill the batch',
      () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 4; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
      const TodoFollowupGenerationJob(
        todoId: 'todo_auto_1',
        triggerKind: 'auto_create',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 10,
      ),
    ];

    final plans = buildTodoFollowupGenerationPassPlans(previewJobs);

    expect(plans, hasLength(2));
    expect(plans[0].hasManualRegenerateDueJob, isTrue);
    expect(plans[0].jobs, hasLength(4));
    expect(plans[1].hasManualRegenerateDueJob, isFalse);
    expect(
      plans[1].jobs.map((job) => job.todoId).toList(growable: false),
      const <String>['todo_auto_1'],
    );
  });

  test('preview loader discovers auto jobs beyond deep manual backlog',
      () async {
    final store = _PreviewStore(
      jobs: <TodoFollowupGenerationJob>[
        for (var index = 0; index < 600; index += 1)
          TodoFollowupGenerationJob(
            todoId: 'todo_manual_$index',
            triggerKind: 'manual_regenerate',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: true,
            taskTypeHint: 'research',
            createdAtMs: index,
            updatedAtMs: index,
          ),
        const TodoFollowupGenerationJob(
          todoId: 'todo_auto_deep',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 601,
          updatedAtMs: 601,
        ),
      ],
    );

    final previewJobs = await loadTodoFollowupGenerationPreviewJobs(
      store,
      nowMs: 0,
      batchLimit: 5,
    );

    expect(previewJobs, hasLength(5));
    expect(
      previewJobs.where((job) => job.triggerKind == 'manual_regenerate'),
      hasLength(4),
    );
    expect(previewJobs.any((job) => job.todoId == 'todo_auto_deep'), isTrue);
    expect(store.requestedLimits, contains(640));
  });

  test('preview loader caps refetch expansion for deep manual backlog',
      () async {
    final store = _PreviewStore(
      jobs: <TodoFollowupGenerationJob>[
        for (var index = 0; index < 2000; index += 1)
          TodoFollowupGenerationJob(
            todoId: 'todo_manual_$index',
            triggerKind: 'manual_regenerate',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: true,
            taskTypeHint: 'research',
            createdAtMs: index,
            updatedAtMs: index,
          ),
      ],
    );

    final previewJobs = await loadTodoFollowupGenerationPreviewJobs(
      store,
      nowMs: 0,
      batchLimit: 5,
    );

    expect(previewJobs, hasLength(5));
    expect(
      previewJobs.every((job) => job.triggerKind == 'manual_regenerate'),
      isTrue,
    );
    expect(store.requestedLimits.last, 640);
    expect(store.requestedLimits.every((limit) => limit <= 640), isTrue);
  });

  test('auto-job loader overfetches past leading manual backlog', () async {
    final store = _PreviewStore(
      jobs: <TodoFollowupGenerationJob>[
        for (var index = 0; index < 4; index += 1)
          TodoFollowupGenerationJob(
            todoId: 'todo_manual_$index',
            triggerKind: 'manual_regenerate',
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            includeManualFollowups: true,
            taskTypeHint: 'research',
            createdAtMs: index,
            updatedAtMs: index,
          ),
        const TodoFollowupGenerationJob(
          todoId: 'todo_auto_deep',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 99,
          updatedAtMs: 99,
        ),
      ],
    );

    final jobs = await loadDueAutoFollowupGenerationJobs(
      store,
      nowMs: 0,
      limit: 1,
    );

    expect(jobs.map((job) => job.todoId).toList(growable: false),
        const <String>['todo_auto_deep']);
    expect(store.requestedLimits, orderedEquals(<int>[2, 4, 8]));
  });
}

final class _PreviewStore implements TodoFollowupGenerationStore {
  _PreviewStore({required this.jobs});

  final List<TodoFollowupGenerationJob> jobs;
  final List<int> requestedLimits = <int>[];

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    requestedLimits.add(limit);
    return jobs.take(limit).toList(growable: false);
  }

  @override
  Future<List<TodoFollowupGenerationJob>> listDueAutoJobs({
    required int nowMs,
    int limit = 1,
  }) async =>
      jobs
          .where((job) => job.triggerKind != 'manual_regenerate')
          .take(limit)
          .toList(growable: false);
  @override
  Future<Todo?> getTodo(String todoId) {
    throw UnimplementedError();
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) {
    throw UnimplementedError();
  }

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) {
    throw UnimplementedError();
  }
}
