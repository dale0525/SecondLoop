import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('runner treats claim conflict as job update so gate keeps draining',
      () async {
    final runner = SemanticParseAutoActionsRunner(
      store: _ClaimConflictStore(),
      client: const _UnusedClient(),
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 3, 26, 12, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(result.didUpdateJobs, isTrue);
  });
}

final class _ClaimConflictStore implements SemanticParseAutoActionsStore {
  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return const <SemanticParseAutoActionJob>[
      SemanticParseAutoActionJob(
        messageId: 'msg:claim_conflict_only',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        createdAtMs: 0,
      ),
    ];
  }

  @override
  Future<SemanticParseJob?> getJob(String messageId) async => null;

  @override
  Future<SemanticParseMessageInput?> getMessageInput(String messageId) async {
    return const SemanticParseMessageInput(
      sourceText: 'ignored',
      analysisText: '买牛奶',
      allowCreate: true,
    );
  }

  @override
  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
    List<String> preferredTodoIds = const <String>[],
  }) async =>
      const <SemanticParseTodoCandidate>[];

  @override
  Future<int?> claimJobRunning({
    required String messageId,
    required int nowMs,
  }) async =>
      null;

  @override
  Future<bool> markJobSucceededIfCurrentAttempt(
    SemanticParseJobSucceededArgs args, {
    required int expectedAttemptId,
  }) async =>
      false;

  @override
  Future<bool> markJobFailedIfCurrentAttempt(
    SemanticParseJobFailedArgs args, {
    required int expectedAttemptId,
  }) async =>
      false;

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {}

  @override
  Future<bool> markJobCanceledIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async =>
      false;

  @override
  Future<List<String>?> completeNoActionIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async =>
      throw UnimplementedError();

  @override
  Future<bool> completeCreateTodoIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
    required List<String> checklistSuggestions,
    required String checklistSource,
    String? checklistGenerationKey,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async =>
      throw UnimplementedError();

  @override
  Future<bool> completeFollowupIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    String? todoTitle,
    required String newStatus,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
    int? expectedAttemptId,
  }) async {
    return const SemanticParseTagApplyResult(
      appliedCount: 0,
      appliedTagIds: <String>[],
    );
  }

  @override
  Future<String?> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
    int? expectedAttemptId,
  }) async =>
      null;

  @override
  Future<void> upsertGeneratedChecklistSuggestions({
    required String messageId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
    int? expectedAttemptId,
  }) async {}

  @override
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
    int? expectedAttemptId,
  }) async =>
      null;
}

final class _UnusedClient implements SemanticParseAutoActionsClient {
  const _UnusedClient();

  @override
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required Duration timeout,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> generateChecklistSuggestions({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  }) async =>
      throw UnimplementedError();
}
