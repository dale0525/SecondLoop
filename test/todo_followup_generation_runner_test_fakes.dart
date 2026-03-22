part of 'todo_followup_generation_runner_test.dart';

final class _FakeStore implements TodoFollowupGenerationStore {
  _FakeStore({
    required List<TodoFollowupGenerationJob> jobs,
    required Map<String, Todo> todos,
    Map<String, List<TodoActivity>>? activitiesByTodoId,
    Map<String, List<TodoFollowupSuggestion>>? suggestionsByTodoId,
  })  : _jobs = List<TodoFollowupGenerationJob>.from(jobs),
        _todos = Map<String, Todo>.from(todos),
        _activitiesByTodoId = <String, List<TodoActivity>>{
          for (final entry
              in (activitiesByTodoId ?? const <String, List<TodoActivity>>{})
                  .entries)
            entry.key: List<TodoActivity>.from(entry.value),
        },
        _suggestionsByTodoId = <String, List<TodoFollowupSuggestion>>{
          for (final entry in (suggestionsByTodoId ??
                  const <String, List<TodoFollowupSuggestion>>{})
              .entries)
            entry.key: List<TodoFollowupSuggestion>.from(entry.value),
        };

  final List<TodoFollowupGenerationJob> _jobs;
  final Map<String, Todo> _todos;
  final Map<String, List<TodoActivity>> _activitiesByTodoId;
  final Map<String, List<TodoFollowupSuggestion>> _suggestionsByTodoId;

  String? lastSucceededTodoId;
  String? lastSkippedTodoId;
  String? lastFailedTodoId;
  String? lastCanceledTodoId;
  int? lastFailedNowMs;
  int? lastFailedNextRetryAtMs;
  List<String> lastDismissedSuggestionIds = <String>[];
  List<TodoFollowupSuggestionDraftInput> lastUpsertedSuggestions =
      <TodoFollowupSuggestionDraftInput>[];

  List<TodoFollowupSuggestion> pendingSuggestionsFor(String todoId) {
    final items =
        _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[];
    return items
        .where((item) => item.state == 'pending')
        .toList(growable: false);
  }

  @override
  Future<Todo?> getTodo(String todoId) async => _todos[todoId];

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) async =>
      List<TodoActivity>.from(
          _activitiesByTodoId[todoId] ?? const <TodoActivity>[]);

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) async =>
      List<TodoFollowupSuggestion>.from(
        _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[],
      );

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async =>
      List<TodoFollowupGenerationJob>.from(_jobs.take(limit));

  @override
  Future<List<TodoFollowupGenerationJob>> listDueAutoJobs({
    required int nowMs,
    int limit = 1,
  }) async =>
      _jobs
          .where((job) => job.triggerKind != 'manual_regenerate')
          .take(limit)
          .toList(growable: false);

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    lastDismissedSuggestionIds = List<String>.from(suggestionIds);
    _suggestionsByTodoId[todoId] =
        (_suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[])
            .where((item) => !suggestionIds.contains(item.id))
            .toList(growable: false);
  }

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) async {
    lastCanceledTodoId = todoId;
  }

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    lastFailedTodoId = todoId;
    lastFailedNowMs = nowMs;
    lastFailedNextRetryAtMs = nextRetryAtMs;
  }

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) async {
    lastSkippedTodoId = todoId;
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) async {
    lastSucceededTodoId = todoId;
  }

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {
    lastUpsertedSuggestions =
        List<TodoFollowupSuggestionDraftInput>.from(suggestions);
    final next = List<TodoFollowupSuggestion>.from(
      _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[],
    );
    for (final suggestion in suggestions) {
      final content = suggestion.content.trim();
      final normalizedContent = _normalizePendingSuggestionContent(content);
      if (normalizedContent.isEmpty) continue;
      final existingIndex = next.indexWhere(
        (item) =>
            item.state == 'pending' &&
            _normalizePendingSuggestionContent(item.content) ==
                normalizedContent,
      );
      if (existingIndex != -1) {
        final existing = next[existingIndex];
        next[existingIndex] = TodoFollowupSuggestion(
          id: existing.id,
          todoId: existing.todoId,
          content: content,
          state: existing.state,
          source: source,
          generationMode: suggestion.generationMode,
          generationKey: generationKey,
          citationsJson: suggestion.citationsJson,
          createdAtMs: existing.createdAtMs,
          updatedAtMs: existing.updatedAtMs,
          dismissedAtMs: existing.dismissedAtMs,
          appliedActivityId: existing.appliedActivityId,
        );
        continue;
      }
      next.add(
        TodoFollowupSuggestion(
          id: 'generated_${next.length + 1}',
          todoId: todoId,
          content: content,
          state: 'pending',
          source: source,
          generationMode: suggestion.generationMode,
          generationKey: generationKey,
          citationsJson: suggestion.citationsJson,
          createdAtMs: 0,
          updatedAtMs: 0,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      );
    }
    _suggestionsByTodoId[todoId] = next;
  }
}

String _normalizePendingSuggestionContent(String raw) {
  return raw
      .split(RegExp(r'\s+'))
      .where((item) => item.isNotEmpty)
      .join(' ')
      .trim()
      .toLowerCase();
}

final class _FakeClient implements TodoFollowupGenerationClient {
  _FakeClient({
    this.responseByMode =
        const <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{},
    this.errorsByMode = const <TodoFollowupGenerationMode, Object>{},
  });

  @override
  final String source = 'cloud';

  final Map<TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>
      responseByMode;
  final Map<TodoFollowupGenerationMode, Object> errorsByMode;
  final List<TodoFollowupGenerationMode> requestedModes =
      <TodoFollowupGenerationMode>[];
  List<String> lastManualFollowups = <String>[];
  String? lastTaskContext;

  @override
  Future<TodoFollowupSuggestionDraft?> generate({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required TodoFollowupGenerationMode generationMode,
    required List<String> manualFollowups,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  }) async {
    requestedModes.add(generationMode);
    lastManualFollowups = List<String>.from(manualFollowups);
    lastTaskContext = taskContext;
    final error = errorsByMode[generationMode];
    if (error != null) throw error;
    return responseByMode[generationMode];
  }
}
