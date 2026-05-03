import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/core/secretary/internal_tool_registry.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/src/rust/db.dart';

import 'semantic_parse_local_first_runner_test_support.dart' as support;

void main() {
  test('semantic todo automation writes a capture secretary run', () async {
    final audit = _FakeSecretaryAuditRecorder();
    final store = _FakeSemanticStore();
    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: const _FakeSemanticClient(),
      secretaryAuditRecorder: audit,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 4, 29, 9),
    );

    final result = await runner.runOnce(
      localeTag: 'en-US',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(audit.runs.single.triggerKind, 'capture');
    expect(audit.runs.single.route, 'local_rules');
    expect(audit.runs.single.inputSummary, contains('msg:audit'));
    expect(audit.toolCalls.single.toolName, 'todo.create');
    expect(audit.toolCalls.single.requiresConfirmation, isFalse);
    expect(audit.toolCalls.single.inputJson, contains('msg:audit'));
    expect(audit.toolCalls.single.outputJson, contains('todo:msg:audit'));
  });

  test('semantic todo command automation writes a tool-specific secretary run',
      () async {
    final audit = _FakeSecretaryAuditRecorder();
    final store = support.FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:priority',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:priority': 'Make invoice priority higher'
      },
      openCandidates: const [
        SemanticParseTodoCandidate(
          id: 'todo:invoice',
          title: 'invoice',
          status: 'open',
        ),
      ],
    );
    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: support.FakeSemanticParseClient(),
      secretaryAuditRecorder: audit,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 4, 29, 9),
    );

    final result = await runner.runOnce(
      localeTag: 'en-US',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(audit.runs.single.triggerKind, 'capture');
    expect(audit.toolCalls.single.toolName, 'todo.priority.set');
    expect(audit.toolCalls.single.requiresConfirmation, isFalse);
    expect(audit.toolCalls.single.inputJson, contains('msg:priority'));
    expect(audit.toolCalls.single.outputJson, contains('todo:invoice'));
  });
}

final class _FakeSecretaryAuditRecorder implements SecretaryAuditRecorder {
  final List<SecretaryAuditRunDraft> runs = <SecretaryAuditRunDraft>[];
  final List<SecretaryToolCallDraft> toolCalls = <SecretaryToolCallDraft>[];

  @override
  Future<void> recordRun(SecretaryAuditRunDraft draft) async {
    runs.add(draft);
    toolCalls.addAll(draft.toolCalls);
  }
}

final class _FakeSemanticStore implements SemanticParseAutoActionsStore {
  SemanticParseJob? _currentJob;

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return const [
      SemanticParseAutoActionJob(
        messageId: 'msg:audit',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        createdAtMs: 0,
      ),
    ];
  }

  @override
  Future<SemanticParseJob?> getJob(String messageId) async => _currentJob;

  @override
  Future<SemanticParseMessageInput?> getMessageInput(String messageId) async {
    return const SemanticParseMessageInput(
      sourceText: 'Tomorrow submit the visa form',
      analysisText: 'Tomorrow submit the visa form',
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
    return const <SemanticParseTodoCandidate>[];
  }

  @override
  Future<int?> claimJobRunning({
    required String messageId,
    required int nowMs,
  }) async {
    _currentJob = _job(messageId, 'running', 1, nowMs);
    return 1;
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
    _currentJob = _job(messageId, 'succeeded', expectedAttemptId, nowMs);
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
    _currentJob = _job(messageId, 'succeeded', expectedAttemptId, nowMs);
    return const <String>[];
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
    _currentJob = _job(messageId, 'succeeded', expectedAttemptId, nowMs);
    return true;
  }

  @override
  Future<bool> markJobFailedIfCurrentAttempt(
    SemanticParseJobFailedArgs args, {
    required int expectedAttemptId,
  }) async {
    _currentJob = _job(args.messageId, 'failed', expectedAttemptId, args.nowMs);
    return true;
  }

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {
    _currentJob = _job(messageId, 'canceled', 1, nowMs);
  }

  @override
  Future<bool> markJobCanceledIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    _currentJob = _job(messageId, 'canceled', expectedAttemptId, nowMs);
    return true;
  }

  @override
  Future<bool> markJobSucceededIfCurrentAttempt(
    SemanticParseJobSucceededArgs args, {
    required int expectedAttemptId,
  }) async {
    _currentJob =
        _job(args.messageId, 'succeeded', expectedAttemptId, args.nowMs);
    return true;
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
    return null;
  }

  SemanticParseJob _job(
    String messageId,
    String status,
    int attemptId,
    int nowMs,
  ) {
    return SemanticParseJob(
      messageId: messageId,
      status: status,
      attemptId: PlatformInt64Util.from(attemptId),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: null,
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      appliedDueChanged: false,
      suggestedTags: null,
      suggestedTagConfidence: null,
      tagSuggestionState: null,
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(0),
      updatedAtMs: PlatformInt64Util.from(nowMs),
    );
  }
}

final class _FakeSemanticClient implements SemanticParseAutoActionsClient {
  const _FakeSemanticClient();

  @override
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  }) async {
    return const <String>[];
  }

  @override
  Future<List<TodoThreadMatch>> retrieveTodoCandidateMatches({
    required String query,
    required int topK,
  }) async {
    return const <TodoThreadMatch>[];
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
    return '{"kind":"create","confidence":1.0,"title":"Submit visa form","status":"open"}';
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
