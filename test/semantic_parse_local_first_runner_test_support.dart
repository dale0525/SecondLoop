import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/core/secretary/todo_command_executor.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/src/rust/db.dart';

final class FakeSemanticParseStore
    implements
        SemanticParseAutoActionsStore,
        SemanticParseTodoCommandCompletingStore {
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
  final Map<String, int> updatedImportanceByTodoId = <String, int>{};
  final Map<String, int> updatedUrgencyByTodoId = <String, int>{};

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
  Future<SecretaryTodoCommandExecutionResult?>
      completeTodoCommandIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required SecretaryTodoCommand command,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    final current = _jobs[messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return null;
    }
    final todoId = command.targetTodoId;
    if (todoId == null || todoId.isEmpty) {
      return null;
    }

    final candidate = _openCandidates
        .where((item) => item.id == todoId)
        .cast<SemanticParseTodoCandidate?>()
        .firstWhere((_) => true, orElse: () => null);
    final previous = Todo(
      id: todoId,
      title: candidate?.title ?? command.targetTitle ?? todoId,
      dueAtMs: candidate?.dueLocalIso == null
          ? null
          : DateTime.tryParse(candidate!.dueLocalIso!)
              ?.toUtc()
              .millisecondsSinceEpoch,
      status: candidate?.status ?? 'open',
      sourceEntryId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
      manualImportanceNudgeScore: 0,
      manualUrgencyNudgeScore: 0,
    );
    final changedFields = <String>[];
    var updatedTitle = previous.title;
    var updatedStatus = previous.status;
    var updatedDueAtMs = previous.dueAtMs;
    var updatedImportance = previous.manualImportanceNudgeScore ?? 0;
    var updatedUrgency = previous.manualUrgencyNudgeScore ?? 0;

    switch (command.kind) {
      case SecretaryTodoCommandKind.updateTitle:
        updatedTitle = command.newTitle ?? updatedTitle;
        changedFields.add('title');
        break;
      case SecretaryTodoCommandKind.reschedule:
        if (command.dueAtMs != null) {
          updatedDueAtMs = command.dueAtMs;
          updatedDueByTodoId[todoId] = command.dueAtMs!;
          changedFields.add('due_at_ms');
        }
        break;
      case SecretaryTodoCommandKind.setStatus:
        if (command.newStatus != null) {
          updatedStatus = command.newStatus!;
          updatedStatusByTodoId[todoId] = command.newStatus!;
          changedFields.add('status');
        }
        break;
      case SecretaryTodoCommandKind.dismiss:
        updatedStatus = 'dismissed';
        updatedStatusByTodoId[todoId] = 'dismissed';
        changedFields.add('status');
        break;
      case SecretaryTodoCommandKind.reprioritize:
        if (command.manualImportanceNudgeScore != null) {
          updatedImportance = command.manualImportanceNudgeScore!;
          updatedImportanceByTodoId[todoId] = updatedImportance;
          changedFields.add('manual_importance_nudge_score');
        }
        if (command.manualUrgencyNudgeScore != null) {
          updatedUrgency = command.manualUrgencyNudgeScore!;
          updatedUrgencyByTodoId[todoId] = updatedUrgency;
          changedFields.add('manual_urgency_nudge_score');
        }
        break;
      case SecretaryTodoCommandKind.create:
      case SecretaryTodoCommandKind.batchUpdate:
      case SecretaryTodoCommandKind.none:
        return null;
    }

    final ok = await markJobSucceededIfCurrentAttempt(
      SemanticParseJobSucceededArgs(
        messageId: messageId,
        appliedActionKind:
            'todo_command:${todoCommandKindWireValue(command.kind)}',
        appliedTodoId: todoId,
        appliedTodoTitle: updatedTitle,
        appliedPrevTodoStatus:
            previous.status == updatedStatus ? null : previous.status,
        nowMs: nowMs,
      ),
      expectedAttemptId: expectedAttemptId,
    );
    if (!ok) return null;

    final updated = Todo(
      id: todoId,
      title: updatedTitle,
      dueAtMs: updatedDueAtMs,
      status: updatedStatus,
      sourceEntryId: previous.sourceEntryId,
      createdAtMs: previous.createdAtMs,
      updatedAtMs: nowMs,
      reviewStage: previous.reviewStage,
      nextReviewAtMs: previous.nextReviewAtMs,
      lastReviewAtMs: previous.lastReviewAtMs,
      manualImportanceNudgeScore: updatedImportance,
      manualUrgencyNudgeScore: updatedUrgency,
    );
    return SecretaryTodoCommandExecutionResult(
      command: command,
      applied: changedFields.isNotEmpty,
      changedFields: changedFields,
      undo: SecretaryTodoCommandUndoSnapshot.fromTodo(previous),
      updatedTodo: updated,
      rejectionReason: changedFields.isEmpty ? 'no_change' : null,
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
      appliedDueChanged: false,
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
    this.retrievedTodoCandidateMatches = const <TodoThreadMatch>[],
    this.retrievedTodoCandidateIds = const <String>[],
  });

  final String? responseJson;
  final List<TodoThreadMatch> retrievedTodoCandidateMatches;
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
    if (retrievedTodoCandidateMatches.isNotEmpty) {
      return retrievedTodoCandidateMatches
          .take(topK)
          .map((match) => match.todoId)
          .toList(growable: false);
    }
    return List<String>.from(retrievedTodoCandidateIds);
  }

  @override
  Future<List<TodoThreadMatch>> retrieveTodoCandidateMatches({
    required String query,
    required int topK,
  }) async {
    retrieveRequests += 1;
    if (retrievedTodoCandidateMatches.isNotEmpty) {
      return retrievedTodoCandidateMatches.take(topK).toList(growable: false);
    }
    final seen = <String>{};
    String? topTodoId;
    for (final rawTodoId in retrievedTodoCandidateIds.take(topK)) {
      final todoId = rawTodoId.trim();
      if (todoId.isEmpty || !seen.add(todoId)) continue;
      topTodoId ??= todoId;
      if (seen.length > 1) {
        return const <TodoThreadMatch>[];
      }
    }
    if (topTodoId == null) {
      return const <TodoThreadMatch>[];
    }
    return <TodoThreadMatch>[
      TodoThreadMatch(todoId: topTodoId, distance: 0.12),
    ];
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
