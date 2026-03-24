import 'dart:async';
import 'dart:convert';

import '../../src/rust/db.dart';
import 'todo_followup_suggestions_ai.dart';
import 'todo_followup_task_classifier.dart';

abstract class TodoFollowupGenerationStore {
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  });

  Future<List<TodoFollowupGenerationJob>> listDueAutoJobs({
    required int nowMs,
    int limit = 1,
  });

  Future<TodoFollowupGenerationJob?> getJob(String todoId);

  Future<Todo?> getTodo(String todoId);

  Future<List<TodoActivity>> listTodoActivities(String todoId);

  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
      String todoId);

  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  });

  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  });

  Future<bool> upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim({
    required String todoId,
    required int jobStartedAtMs,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  });

  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  });

  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  });

  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  });

  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  });

  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  });
}

abstract class TodoFollowupGenerationClient {
  String get source;

  Future<TodoFollowupSuggestionDraft?> generate({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required TodoFollowupGenerationMode generationMode,
    required List<String> manualFollowups,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  });
}

const kTodoFollowupGenerationMaxManualAttempts = 5;
const _kTodoFollowupGenerationJobNotClaimedError =
    'todo_followup_generation_job_not_claimed';

final class TodoFollowupGenerationRunnerSettings {
  const TodoFollowupGenerationRunnerSettings({
    required this.hardTimeout,
    this.batchLimit = 5,
    this.maxAutoAttempts = 3,
    this.maxManualAttempts = kTodoFollowupGenerationMaxManualAttempts,
  });

  final Duration hardTimeout;
  final int batchLimit;
  final int maxAutoAttempts;
  final int maxManualAttempts;
}

final class TodoFollowupGenerationRunResult {
  const TodoFollowupGenerationRunResult({
    required this.processed,
    required this.didMutateAny,
    required this.didUpdateJobs,
    required this.earliestNextRetryAtMs,
  });

  final int processed;
  final bool didMutateAny;
  final bool didUpdateJobs;
  final int? earliestNextRetryAtMs;
}

typedef TodoFollowupNowMs = int Function();

final class TodoFollowupGenerationRunner {
  TodoFollowupGenerationRunner({
    required this.store,
    required this.client,
    required this.settings,
    TodoFollowupNowMs? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final TodoFollowupGenerationStore store;
  final TodoFollowupGenerationClient client;
  final TodoFollowupGenerationRunnerSettings settings;
  final TodoFollowupNowMs _nowMs;

  Future<TodoFollowupGenerationRunResult> runOnce({
    required String localeTag,
  }) async {
    final nowMs = _nowMs();
    final jobs = await store.listDueJobs(
      nowMs: nowMs,
      limit: settings.batchLimit,
    );

    var processed = 0;
    var didMutateAny = false;
    var didUpdateJobs = false;
    int? earliestNextRetryAtMs;

    for (final job in jobs) {
      if (job.status != 'pending' &&
          job.status != 'failed' &&
          job.status != 'running') {
        continue;
      }

      final jobStartedAtMs = _nowMs();
      final todo = await store.getTodo(job.todoId);
      if (todo == null) {
        await store.markJobCanceled(
          todoId: job.todoId,
          nowMs: _nowMs(),
        );
        didUpdateJobs = true;
        processed++;
        continue;
      }

      try {
        await store.markJobRunning(todoId: job.todoId, nowMs: jobStartedAtMs);
        didUpdateJobs = true;

        final taskType = _resolveTaskType(job, todo);
        if (!taskType.allowsAutoFollowup) {
          await _markJobSkippedIfStillRunning(
            todoId: job.todoId,
            jobStartedAtMs: jobStartedAtMs,
            nowMs: _nowMs(),
          );
          processed++;
          continue;
        }

        final existingSuggestions =
            await store.listTodoFollowupSuggestions(job.todoId);
        final pendingSuggestions = existingSuggestions
            .where((item) => item.state == 'pending')
            .toList(growable: false);
        final pendingSuggestionIds =
            pendingSuggestions.map((item) => item.id).toList(growable: false);

        if (job.triggerKind != 'manual_regenerate' &&
            pendingSuggestionIds.isNotEmpty) {
          await _markJobSucceededIfStillRunning(
            todoId: job.todoId,
            jobStartedAtMs: jobStartedAtMs,
            nowMs: _nowMs(),
          );
          processed++;
          continue;
        }

        final activities = await store.listTodoActivities(job.todoId);
        final manualFollowups = job.includeManualFollowups
            ? _collectManualFollowups(activities)
            : const <String>[];
        final contextActivities = job.includeManualFollowups
            ? activities
                .where((activity) =>
                    activity.activityType != 'followup_information' &&
                    activity.activityType != 'note')
                .toList(growable: false)
            : activities;
        final taskContext = buildTodoFollowupSuggestionContext(
          todo: todo,
          activities: contextActivities,
        );

        final suggestion = await _generateSuggestion(
          todo: todo,
          taskContext: taskContext,
          localeTag: localeTag,
          manualFollowups: manualFollowups,
        );
        if (suggestion == null) {
          throw StateError('Empty follow-up suggestion');
        }

        final generationKey =
            'followup:${job.triggerKind}:${taskType.wireValue}:$jobStartedAtMs';
        final generatedSuggestions = <TodoFollowupSuggestionDraftInput>[
          TodoFollowupSuggestionDraftInput(
            content: suggestion.content,
            generationMode: suggestion.mode.wireValue,
            citationsJson: suggestion.citations.isEmpty
                ? null
                : encodeTodoFollowupCitationsJson(suggestion.citations),
          ),
        ];

        if (!await _isStillRunningAttempt(
          todoId: job.todoId,
          jobStartedAtMs: jobStartedAtMs,
        )) {
          processed++;
          continue;
        }

        final didPersistSuggestions =
            await store.upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
          todoId: job.todoId,
          jobStartedAtMs: jobStartedAtMs,
          suggestions: generatedSuggestions,
          source: client.source,
          generationKey: generationKey,
        );
        if (!didPersistSuggestions) {
          processed++;
          continue;
        }

        final updatedSuggestions =
            await store.listTodoFollowupSuggestions(job.todoId);
        final updatedPendingSuggestions = updatedSuggestions
            .where((item) => item.state == 'pending')
            .toList(growable: false);
        final createdPendingSuggestions = updatedPendingSuggestions
            .where((item) => item.generationKey == generationKey)
            .toList(growable: false);
        if (createdPendingSuggestions.isNotEmpty) {
          didMutateAny = true;
        }

        if (job.includeManualFollowups && pendingSuggestionIds.isNotEmpty) {
          final previousPendingSuggestionIds = pendingSuggestionIds.toSet();
          final retainedPendingSuggestionIds =
              createdPendingSuggestions.map((item) => item.id).toSet();
          final stalePendingSuggestionIds = updatedPendingSuggestions
              .where(
                (item) =>
                    previousPendingSuggestionIds.contains(item.id) &&
                    !retainedPendingSuggestionIds.contains(item.id),
              )
              .map((item) => item.id)
              .toList(growable: false);
          if (stalePendingSuggestionIds.isNotEmpty) {
            await store.dismissTodoFollowupSuggestions(
              todoId: job.todoId,
              suggestionIds: stalePendingSuggestionIds,
            );
            didMutateAny = true;
          }
        }

        await _markJobSucceededIfStillRunning(
          todoId: job.todoId,
          jobStartedAtMs: jobStartedAtMs,
          nowMs: _nowMs(),
        );
        processed++;
      } catch (error) {
        if (_isTodoFollowupGenerationJobNotClaimedError(error)) {
          continue;
        }
        final attempts = job.attempts.toInt() + 1;
        final failedAtMs = _nowMs();
        if (job.triggerKind == 'manual_regenerate') {
          if (attempts >= settings.maxManualAttempts) {
            final didFinalize = await _markJobCanceledIfStillRunning(
              todoId: job.todoId,
              jobStartedAtMs: jobStartedAtMs,
              nowMs: failedAtMs,
            );
            didUpdateJobs = didUpdateJobs || didFinalize;
            processed++;
            continue;
          }
          final nextRetryAtMs = failedAtMs + _retryDelayMsForAttempt(attempts);
          final didFinalize = await _markJobFailedIfStillRunning(
            todoId: job.todoId,
            jobStartedAtMs: jobStartedAtMs,
            attempts: attempts,
            nextRetryAtMs: nextRetryAtMs,
            lastError: '$error',
            nowMs: failedAtMs,
          );
          earliestNextRetryAtMs = _minRetryAtMs(
            earliestNextRetryAtMs,
            nextRetryAtMs,
          );
          didUpdateJobs = didUpdateJobs || didFinalize;
          continue;
        }

        if (attempts >= settings.maxAutoAttempts) {
          final didFinalize = await _markJobCanceledIfStillRunning(
            todoId: job.todoId,
            jobStartedAtMs: jobStartedAtMs,
            nowMs: failedAtMs,
          );
          didUpdateJobs = didUpdateJobs || didFinalize;
          processed++;
          continue;
        }

        final nextRetryAtMs = failedAtMs + _retryDelayMsForAttempt(attempts);
        final didFinalize = await _markJobFailedIfStillRunning(
          todoId: job.todoId,
          jobStartedAtMs: jobStartedAtMs,
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          lastError: '$error',
          nowMs: failedAtMs,
        );
        earliestNextRetryAtMs = _minRetryAtMs(
          earliestNextRetryAtMs,
          nextRetryAtMs,
        );
        didUpdateJobs = didUpdateJobs || didFinalize;
      }
    }

    return TodoFollowupGenerationRunResult(
      processed: processed,
      didMutateAny: didMutateAny,
      didUpdateJobs: didUpdateJobs,
      earliestNextRetryAtMs: earliestNextRetryAtMs,
    );
  }

  Future<bool> _isStillRunningAttempt({
    required String todoId,
    required int jobStartedAtMs,
  }) async {
    final currentJob = await store.getJob(todoId);
    if (currentJob == null) {
      return false;
    }
    return currentJob.status == 'running' &&
        currentJob.updatedAtMs.toInt() == jobStartedAtMs;
  }

  Future<bool> _markJobSucceededIfStillRunning({
    required String todoId,
    required int jobStartedAtMs,
    required int nowMs,
  }) async {
    if (!await _isStillRunningAttempt(
      todoId: todoId,
      jobStartedAtMs: jobStartedAtMs,
    )) {
      return false;
    }
    await store.markJobSucceeded(todoId: todoId, nowMs: nowMs);
    return true;
  }

  Future<bool> _markJobSkippedIfStillRunning({
    required String todoId,
    required int jobStartedAtMs,
    required int nowMs,
  }) async {
    if (!await _isStillRunningAttempt(
      todoId: todoId,
      jobStartedAtMs: jobStartedAtMs,
    )) {
      return false;
    }
    await store.markJobSkipped(todoId: todoId, nowMs: nowMs);
    return true;
  }

  Future<bool> _markJobCanceledIfStillRunning({
    required String todoId,
    required int jobStartedAtMs,
    required int nowMs,
  }) async {
    if (!await _isStillRunningAttempt(
      todoId: todoId,
      jobStartedAtMs: jobStartedAtMs,
    )) {
      return false;
    }
    await store.markJobCanceled(todoId: todoId, nowMs: nowMs);
    return true;
  }

  Future<bool> _markJobFailedIfStillRunning({
    required String todoId,
    required int jobStartedAtMs,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    if (!await _isStillRunningAttempt(
      todoId: todoId,
      jobStartedAtMs: jobStartedAtMs,
    )) {
      return false;
    }
    await store.markJobFailed(
      todoId: todoId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    );
    return true;
  }

  TodoFollowupTaskType _resolveTaskType(
    TodoFollowupGenerationJob job,
    Todo todo,
  ) {
    final hinted = TodoFollowupTaskType.fromWireValue(job.taskTypeHint);
    if (hinted != TodoFollowupTaskType.unknown) {
      return hinted;
    }
    return classifyTodoFollowupTaskType(todo.title);
  }

  Future<TodoFollowupSuggestionDraft?> _generateSuggestion({
    required Todo todo,
    required String taskContext,
    required String localeTag,
    required List<String> manualFollowups,
  }) async {
    try {
      final webSearchDraft = await client.generate(
        taskTitle: todo.title,
        taskContext: taskContext,
        localeTag: localeTag,
        generationMode: TodoFollowupGenerationMode.webSearch,
        manualFollowups: manualFollowups,
        status: todo.status,
        dueAtMs: todo.dueAtMs?.toInt(),
        timeout: settings.hardTimeout,
      );
      if (webSearchDraft != null) return webSearchDraft;
    } catch (_) {
      // Fall back to model knowledge below.
    }

    return client.generate(
      taskTitle: todo.title,
      taskContext: taskContext,
      localeTag: localeTag,
      generationMode: TodoFollowupGenerationMode.modelKnowledge,
      manualFollowups: manualFollowups,
      status: todo.status,
      dueAtMs: todo.dueAtMs?.toInt(),
      timeout: settings.hardTimeout,
    );
  }
}

bool _isTodoFollowupGenerationJobNotClaimedError(Object error) {
  return '$error'.contains(_kTodoFollowupGenerationJobNotClaimedError);
}

List<String> _collectManualFollowups(List<TodoActivity> activities) {
  final out = <String>[];
  for (final activity in activities) {
    if (activity.activityType != 'note') continue;
    final content = (activity.content ?? '').trim();
    if (content.isEmpty) continue;
    out.add(content);
  }
  return out;
}

int _retryDelayMsForAttempt(int attempts) {
  if (attempts <= 1) return 30 * 1000;
  if (attempts == 2) return 2 * 60 * 1000;
  return 10 * 60 * 1000;
}

int? _minRetryAtMs(int? current, int? candidate) {
  if (candidate == null) {
    return current;
  }
  if (current == null || candidate < current) {
    return candidate;
  }
  return current;
}

String encodeTodoFollowupCitationsJson(
    List<TodoFollowupCitationDraft> citations) {
  return jsonEncode(
    citations
        .map(
          (item) => <String, String>{
            'title': item.title,
            'url': item.url,
            'domain': item.domain,
          },
        )
        .toList(growable: false),
  );
}
