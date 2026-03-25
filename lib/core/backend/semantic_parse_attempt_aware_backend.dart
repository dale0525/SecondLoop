import 'dart:typed_data';

abstract interface class SemanticParseAttemptAwareBackend {
  Future<int> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  });

  Future<bool> markSemanticParseJobFailedIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  });

  Future<bool> markSemanticParseJobSucceededIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  });

  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  });

  Future<List<String>> applySemanticParseTagsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required List<String> suggestedTags,
  });

  Future<String?> upsertTodoFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    int? dueAtMs,
    required String status,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    String? taskTypeHint,
    String? recurrenceRuleJson,
    required int nowMs,
  });

  Future<void> upsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  });

  Future<String?> setTodoStatusFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String newStatus,
  });
}
