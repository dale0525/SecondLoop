part of 'app_backend.dart';

extension AppBackendTodoFollowups on AppBackend {
  Future<List<TodoFollowupSuggestion>>
      upsertGeneratedTodoFollowupSuggestionDraft(
    Uint8List key, {
    required String todoId,
    required TodoFollowupSuggestionDraftInput suggestion,
    required String source,
    String? generationKey,
  }) {
    return upsertGeneratedTodoFollowupSuggestions(
      key,
      todoId: todoId,
      suggestions: <TodoFollowupSuggestionDraftInput>[suggestion],
      source: source,
      generationKey: generationKey,
    );
  }
}
