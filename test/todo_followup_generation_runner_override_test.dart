import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/ai/todo_followup_suggestions_ai.dart';
import 'package:secondloop/src/rust/db.dart';

class _Store implements TodoFollowupGenerationStore {
  _Store({required this.jobs, required this.todos});

  final List<TodoFollowupGenerationJob> jobs;
  final Map<String, Todo> todos;
  String? lastSucceededTodoId;
  String? lastSkippedTodoId;

  @override
  Future<TodoFollowupGenerationJob?> getJob(String todoId) async =>
      jobs.cast<TodoFollowupGenerationJob?>().firstWhere(
            (job) => job?.todoId == todoId,
            orElse: () => null,
          );

  @override
  Future<Todo?> getTodo(String todoId) async => todos[todoId];

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoFollowupGenerationJob>> listDueAutoJobs(
          {required int nowMs, int limit = 1}) async =>
      jobs
          .where((job) => job.triggerKind != 'manual_regenerate')
          .take(limit)
          .toList();

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs(
          {required int nowMs, int limit = 5}) async =>
      jobs.take(limit).toList();

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
          String todoId) async =>
      const <TodoFollowupSuggestion>[];

  @override
  Future<void> dismissTodoFollowupSuggestions(
      {required String todoId, required List<String> suggestionIds}) async {}

  @override
  Future<void> markJobCanceled(
      {required String todoId, required int nowMs}) async {}

  @override
  Future<void> markJobFailed(
      {required String todoId,
      required int attempts,
      required int nextRetryAtMs,
      required String lastError,
      required int nowMs}) async {}

  @override
  Future<void> markJobRunning(
      {required String todoId, required int nowMs}) async {
    final index = jobs.indexWhere((job) => job.todoId == todoId);
    jobs[index] = TodoFollowupGenerationJob(
      todoId: jobs[index].todoId,
      triggerKind: jobs[index].triggerKind,
      status: 'running',
      attempts: jobs[index].attempts,
      nextRetryAtMs: jobs[index].nextRetryAtMs,
      lastError: jobs[index].lastError,
      includeManualFollowups: jobs[index].includeManualFollowups,
      manualOverrideFollowup: jobs[index].manualOverrideFollowup,
      taskTypeHint: jobs[index].taskTypeHint,
      createdAtMs: jobs[index].createdAtMs,
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<void> markJobSkipped(
      {required String todoId, required int nowMs}) async {
    lastSkippedTodoId = todoId;
  }

  @override
  Future<void> markJobSucceeded(
      {required String todoId, required int nowMs}) async {
    lastSucceededTodoId = todoId;
  }

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions(
      {required String todoId,
      required List<TodoFollowupSuggestionDraftInput> suggestions,
      required String source,
      String? generationKey}) async {}

  @override
  Future<bool> upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
          {required String todoId,
          required int jobStartedAtMs,
          required List<TodoFollowupSuggestionDraftInput> suggestions,
          required String source,
          String? generationKey}) async =>
      true;
}

class _Client implements TodoFollowupGenerationClient {
  @override
  String get source => 'test';

  final List<TodoFollowupGenerationMode> requestedModes =
      <TodoFollowupGenerationMode>[];

  @override
  Future<TodoFollowupSuggestionDraft?> generate(
      {required String taskTitle,
      required String taskContext,
      required String localeTag,
      required TodoFollowupGenerationMode generationMode,
      required List<String> manualFollowups,
      String? status,
      int? dueAtMs,
      required Duration timeout}) async {
    requestedModes.add(generationMode);
    return const TodoFollowupSuggestionDraft(
      content: '先补充几个排查方向。',
      mode: TodoFollowupGenerationMode.modelKnowledge,
      citations: <TodoFollowupCitationDraft>[],
    );
  }
}

void main() {
  test('manual regenerate override allows execution task to generate',
      () async {
    final store = _Store(
      jobs: <TodoFollowupGenerationJob>[
        const TodoFollowupGenerationJob(
          todoId: 'todo_override',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          manualOverrideFollowup: true,
          taskTypeHint: 'execution',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_override': Todo(
          id: 'todo_override',
          title: '修复登录页闪退',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _Client();

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastSkippedTodoId, isNull);
    expect(store.lastSucceededTodoId, 'todo_override');
    expect(client.requestedModes, isNotEmpty);
  });
}
