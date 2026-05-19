part of 'native_backend.dart';

Future<List<TodoFollowupSuggestion>> _dartDbListTodoFollowupSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return _sortedTodoFollowupSuggestions(state, todoId);
}

Future<List<TodoFollowupSuggestion>>
    _dartDbUpsertGeneratedTodoFollowupSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<TodoFollowupSuggestionDraftInput> suggestions,
  required String source,
  String? generationKey,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final suggestion in suggestions) {
    final content = suggestion.content.trim();
    final normalizedContent = _normalizeDartTodoFollowupContent(content);
    if (normalizedContent.isEmpty) continue;

    final existing = _sortedTodoFollowupSuggestions(state, todoId)
        .where((item) => item.state == 'pending')
        .cast<TodoFollowupSuggestion?>()
        .firstWhere(
          (item) =>
              item != null &&
              _normalizeDartTodoFollowupContent(item.content) ==
                  normalizedContent,
          orElse: () => null,
        );
    if (existing != null) {
      state.todoFollowupSuggestions[existing.id] =
          _copyDartTodoFollowupSuggestion(
        existing,
        content: content,
        source: source,
        generationMode: suggestion.generationMode,
        generationKey: generationKey,
        citationsJson: suggestion.citationsJson,
        updatedAtMs: now,
      );
      continue;
    }

    final seq = state.nextTodoFollowupSuggestionSeq++;
    final id = 'todo_followup_${seq.toString().padLeft(6, '0')}';
    state.todoFollowupSuggestions[id] = TodoFollowupSuggestion(
      id: id,
      todoId: todoId,
      content: content,
      state: 'pending',
      source: source,
      generationMode: suggestion.generationMode,
      generationKey: generationKey,
      citationsJson: suggestion.citationsJson,
      createdAtMs: now,
      updatedAtMs: now,
      dismissedAtMs: null,
      appliedActivityId: null,
    );
  }
  return _sortedTodoFollowupSuggestions(state, todoId);
}

Future<bool> _dartDbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim({
  required String appDir,
  required List<int> key,
  required String todoId,
  required int jobStartedAtMs,
  required List<TodoFollowupSuggestionDraftInput> suggestions,
  required String source,
  String? generationKey,
}) async {
  await _dartDbUpsertGeneratedTodoFollowupSuggestions(
    appDir: appDir,
    key: key,
    todoId: todoId,
    suggestions: suggestions,
    source: source,
    generationKey: generationKey,
  );
  return true;
}

Future<List<TodoActivity>> _dartDbApplyTodoFollowupSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  final activities = <TodoActivity>[];
  for (final suggestionId in suggestionIds) {
    final suggestion = state.todoFollowupSuggestions[suggestionId];
    if (suggestion == null ||
        suggestion.todoId != todoId ||
        suggestion.state != 'pending') {
      continue;
    }
    final seq = state.nextTodoActivitySeq++;
    final activityId = 'todo_activity_${seq.toString().padLeft(6, '0')}';
    final activity = TodoActivity(
      id: activityId,
      todoId: todoId,
      activityType: 'followup_information',
      fromStatus: null,
      toStatus: null,
      content: suggestion.content,
      sourceMessageId: null,
      createdAtMs: now,
    );
    state.todoActivities[activity.id] = activity;
    state.todoFollowupSuggestions[suggestion.id] =
        _copyDartTodoFollowupSuggestion(
      suggestion,
      state: 'applied',
      appliedActivityId: activity.id,
      updatedAtMs: now,
    );
    activities.add(activity);
  }
  return activities;
}

Future<void> _dartDbDismissTodoFollowupSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final suggestionId in suggestionIds) {
    final suggestion = state.todoFollowupSuggestions[suggestionId];
    if (suggestion == null || suggestion.todoId != todoId) continue;
    state.todoFollowupSuggestions[suggestion.id] =
        _copyDartTodoFollowupSuggestion(
      suggestion,
      state: 'dismissed',
      dismissedAtMs: now,
      updatedAtMs: now,
    );
  }
}

Future<void> _dartDbDismissAllTodoFollowupSuggestions({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  for (final suggestion in _sortedTodoFollowupSuggestions(state, todoId)) {
    if (suggestion.state != 'pending') continue;
    state.todoFollowupSuggestions[suggestion.id] =
        _copyDartTodoFollowupSuggestion(
      suggestion,
      state: 'dismissed',
      dismissedAtMs: now,
      updatedAtMs: now,
    );
  }
}

List<TodoFollowupSuggestion> _sortedTodoFollowupSuggestions(
  _DartNativeRuntimeState state,
  String todoId,
) {
  final suggestions = state.todoFollowupSuggestions.values
      .where((suggestion) => suggestion.todoId == todoId)
      .toList(growable: false);
  suggestions.sort((a, b) {
    final byCreatedAt = a.createdAtMs.compareTo(b.createdAtMs);
    return byCreatedAt != 0 ? byCreatedAt : a.id.compareTo(b.id);
  });
  return suggestions;
}

String _normalizeDartTodoFollowupContent(String content) {
  return content.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

TodoFollowupSuggestion _copyDartTodoFollowupSuggestion(
  TodoFollowupSuggestion suggestion, {
  String? content,
  String? state,
  String? source,
  String? generationMode,
  String? generationKey,
  String? citationsJson,
  PlatformInt64? dismissedAtMs,
  String? appliedActivityId,
  PlatformInt64? updatedAtMs,
}) {
  return TodoFollowupSuggestion(
    id: suggestion.id,
    todoId: suggestion.todoId,
    content: content ?? suggestion.content,
    state: state ?? suggestion.state,
    source: source ?? suggestion.source,
    generationMode: generationMode ?? suggestion.generationMode,
    generationKey: generationKey ?? suggestion.generationKey,
    citationsJson: citationsJson ?? suggestion.citationsJson,
    createdAtMs: suggestion.createdAtMs,
    updatedAtMs: updatedAtMs ?? suggestion.updatedAtMs,
    dismissedAtMs: dismissedAtMs ?? suggestion.dismissedAtMs,
    appliedActivityId: appliedActivityId ?? suggestion.appliedActivityId,
  );
}
