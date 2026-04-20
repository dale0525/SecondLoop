import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

final class FakeSemanticParseStore implements SemanticParseAutoActionsStore {
  FakeSemanticParseStore({
    required List<SemanticParseAutoActionJob> jobs,
    required Map<String, String> messages,
    List<SemanticParseTodoCandidate> openCandidates =
        const <SemanticParseTodoCandidate>[],
  })  : _messages = Map<String, String>.from(messages),
        _openCandidates =
            List<SemanticParseTodoCandidate>.from(openCandidates) {
    for (final job in jobs) {
      _jobs[job.messageId] = _job(
        messageId: job.messageId,
        status: job.status,
        attemptId: 0,
        attempts: job.attempts,
        nextRetryAtMs: job.nextRetryAtMs,
        createdAtMs: job.createdAtMs,
        updatedAtMs: 0,
      );
    }
  }

  final Map<String, SemanticParseJob> _jobs = <String, SemanticParseJob>{};
  final Map<String, String> _messages;
  final List<SemanticParseTodoCandidate> _openCandidates;

  final List<String> createdTodoIds = <String>[];
  final Map<String, String> updatedStatusByTodoId = <String, String>{};
  final Map<String, int> updatedDueByTodoId = <String, int>{};

  SemanticParseJob? jobState(String messageId) => _jobs[messageId];

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return _jobs.values
        .take(limit)
        .map(
          (job) => SemanticParseAutoActionJob(
            messageId: job.messageId,
            status: job.status,
            attempts: job.attempts.toInt(),
            nextRetryAtMs: job.nextRetryAtMs?.toInt(),
            createdAtMs: job.createdAtMs.toInt(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SemanticParseJob?> getJob(String messageId) async => _jobs[messageId];

  @override
  Future<SemanticParseMessageInput?> getMessageInput(String messageId) async {
    final text = _messages[messageId];
    if (text == null) return null;
    return SemanticParseMessageInput(
      sourceText: text,
      analysisText: text,
      allowCreate: true,
    );
  }

  @override
  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
    List<String> preferredTodoIds = const <String>[],
  }) async {
    return _openCandidates.take(limit).toList(growable: false);
  }

  @override
  Future<int?> claimJobRunning({
    required String messageId,
    required int nowMs,
  }) async {
    final current = _jobs[messageId];
    if (current == null) return null;
    final nextAttempt = current.attemptId.toInt() + 1;
    _jobs[messageId] = _job(
      messageId: messageId,
      status: 'running',
      attemptId: nextAttempt,
      attempts: current.attempts.toInt(),
      nextRetryAtMs: current.nextRetryAtMs?.toInt(),
      createdAtMs: current.createdAtMs.toInt(),
      updatedAtMs: nowMs,
    );
    return nextAttempt;
  }

  @override
  Future<bool> markJobSucceededIfCurrentAttempt(
    SemanticParseJobSucceededArgs args, {
    required int expectedAttemptId,
  }) async {
    final current = _jobs[args.messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    _jobs[args.messageId] = _job(
      messageId: args.messageId,
      status: 'succeeded',
      attemptId: expectedAttemptId,
      attempts: current.attempts.toInt(),
      nextRetryAtMs: current.nextRetryAtMs?.toInt(),
      createdAtMs: current.createdAtMs.toInt(),
      updatedAtMs: args.nowMs,
      appliedActionKind: args.appliedActionKind,
      appliedTodoId: args.appliedTodoId,
      appliedTodoTitle: args.appliedTodoTitle,
      appliedPrevTodoStatus: args.appliedPrevTodoStatus,
    );
    return true;
  }

  @override
  Future<bool> markJobFailedIfCurrentAttempt(
    SemanticParseJobFailedArgs args, {
    required int expectedAttemptId,
  }) async {
    final current = _jobs[args.messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    _jobs[args.messageId] = _job(
      messageId: args.messageId,
      status: 'failed',
      attemptId: expectedAttemptId,
      attempts: args.attempts,
      nextRetryAtMs: args.nextRetryAtMs,
      createdAtMs: current.createdAtMs.toInt(),
      updatedAtMs: args.nowMs,
    );
    return true;
  }

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {
    final current = _jobs[messageId]!;
    _jobs[messageId] = _job(
      messageId: messageId,
      status: 'canceled',
      attemptId: current.attemptId.toInt(),
      attempts: current.attempts.toInt(),
      nextRetryAtMs: current.nextRetryAtMs?.toInt(),
      createdAtMs: current.createdAtMs.toInt(),
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<bool> markJobCanceledIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    final current = _jobs[messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    await markJobCanceled(messageId: messageId, nowMs: nowMs);
    return true;
  }

  @override
  Future<List<String>?> completeNoActionIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    final ok = await markJobSucceededIfCurrentAttempt(
      SemanticParseJobSucceededArgs(
        messageId: messageId,
        appliedActionKind: 'none',
        nowMs: nowMs,
      ),
      expectedAttemptId: expectedAttemptId,
    );
    return ok ? const <String>[] : null;
  }

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
  }) async {
    createdTodoIds.add('todo:$messageId');
    return markJobSucceededIfCurrentAttempt(
      SemanticParseJobSucceededArgs(
        messageId: messageId,
        appliedActionKind: 'create',
        appliedTodoId: 'todo:$messageId',
        appliedTodoTitle: title,
        nowMs: nowMs,
      ),
      expectedAttemptId: expectedAttemptId,
    );
  }

  @override
  Future<bool> completeFollowupIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    String? todoTitle,
    String? newStatus,
    int? dueAtMs,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    if (newStatus != null) {
      updatedStatusByTodoId[todoId] = newStatus;
    }
    if (dueAtMs != null) {
      updatedDueByTodoId[todoId] = dueAtMs;
    }
    return markJobSucceededIfCurrentAttempt(
      SemanticParseJobSucceededArgs(
        messageId: messageId,
        appliedActionKind: 'followup',
        appliedTodoId: todoId,
        appliedTodoTitle: todoTitle,
        nowMs: nowMs,
      ),
      expectedAttemptId: expectedAttemptId,
    );
  }

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
  }) async {
    createdTodoIds.add('todo:$messageId');
    return 'todo:$messageId';
  }

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
  }) async {
    updatedStatusByTodoId[todoId] = newStatus;
    return 'open';
  }

  SemanticParseJob _job({
    required String messageId,
    required String status,
    required int attemptId,
    required int attempts,
    int? nextRetryAtMs,
    required int createdAtMs,
    required int updatedAtMs,
    String? appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
  }) {
    return SemanticParseJob(
      messageId: messageId,
      status: status,
      attemptId: attemptId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: null,
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      suggestedTags: null,
      suggestedTagConfidence: null,
      tagSuggestionState: null,
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
    );
  }
}

final class FakeSemanticParseClient implements SemanticParseAutoActionsClient {
  FakeSemanticParseClient({
    this.responseJson,
    this.retrievedTodoCandidateIds = const <String>[],
  });

  final String? responseJson;
  final List<String> retrievedTodoCandidateIds;
  int retrieveRequests = 0;
  int parseRequests = 0;
  String? lastLocalResultJson;
  List<String> lastUnresolvedFields = const <String>[];

  @override
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  }) async {
    retrieveRequests += 1;
    return List<String>.from(retrievedTodoCandidateIds);
  }

  @override
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required String localResultJson,
    required List<String> unresolvedFields,
    required Duration timeout,
  }) async {
    parseRequests += 1;
    lastLocalResultJson = localResultJson;
    lastUnresolvedFields = List<String>.from(unresolvedFields);
    return responseJson ?? '{"kind":"none","confidence":0.0}';
  }

  @override
  Future<List<String>> generateChecklistSuggestions({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  }) async {
    return const <String>[];
  }
}
