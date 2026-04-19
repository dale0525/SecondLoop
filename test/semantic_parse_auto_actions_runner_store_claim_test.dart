import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/semantic_parse_attempt_aware_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('store treats thrown stale-claim as conflict when job already moved on',
      () async {
    final store = BackendSemanticParseAutoActionsStore(
      backend: _ThrowingClaimBackend(
        thrownError: AnyhowException('database busy while claiming'),
        jobsByMessageId: <String, SemanticParseJob>{
          'msg:running': _job(
            messageId: 'msg:running',
            status: 'running',
            attemptId: 3,
          ),
        },
      ),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    final attemptId = await store.claimJobRunning(
      messageId: 'msg:running',
      nowMs: 1000,
    );

    expect(attemptId, isNull);
  });

  test('store rethrows claim failure when job is still claimable', () async {
    final error = AnyhowException('database busy while claiming');
    final store = BackendSemanticParseAutoActionsStore(
      backend: _ThrowingClaimBackend(
        thrownError: error,
        jobsByMessageId: <String, SemanticParseJob>{
          'msg:pending': _job(
            messageId: 'msg:pending',
            status: 'pending',
            attemptId: 0,
          ),
        },
      ),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    expect(
      () => store.claimJobRunning(messageId: 'msg:pending', nowMs: 1000),
      throwsA(same(error)),
    );
  });

  test(
      'store rejects non-atomic no-action completion without attempt-aware backend',
      () async {
    final store = BackendSemanticParseAutoActionsStore(
      backend: _NonAttemptAwareBackend(
        jobsByMessageId: <String, SemanticParseJob>{
          'msg:running': _job(
            messageId: 'msg:running',
            status: 'running',
            attemptId: 4,
          ),
        },
      ),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    expect(
      () => store.completeNoActionIfCurrentAttempt(
        messageId: 'msg:running',
        expectedAttemptId: 4,
        nowMs: 1000,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'store rejects non-atomic create completion without attempt-aware backend',
      () async {
    final store = BackendSemanticParseAutoActionsStore(
      backend: _NonAttemptAwareBackend(
        jobsByMessageId: <String, SemanticParseJob>{
          'msg:running': _job(
            messageId: 'msg:running',
            status: 'running',
            attemptId: 7,
          ),
        },
      ),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    expect(
      () => store.completeCreateTodoIfCurrentAttempt(
        messageId: 'msg:running',
        expectedAttemptId: 7,
        title: 'Test',
        status: 'inbox',
        checklistSuggestions: const <String>[],
        checklistSource: 'test',
        nowMs: 1000,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'store rejects non-atomic followup completion without attempt-aware backend',
      () async {
    final store = BackendSemanticParseAutoActionsStore(
      backend: _NonAttemptAwareBackend(
        jobsByMessageId: <String, SemanticParseJob>{
          'msg:running': _job(
            messageId: 'msg:running',
            status: 'running',
            attemptId: 9,
          ),
        },
      ),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    expect(
      () => store.completeFollowupIfCurrentAttempt(
        messageId: 'msg:running',
        expectedAttemptId: 9,
        todoId: 'todo-1',
        todoTitle: 'Todo',
        newStatus: 'done',
        nowMs: 1000,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('store uses atomic followup completion for due-only updates', () async {
    final backend = _AtomicFollowupBackend(
      jobsByMessageId: <String, SemanticParseJob>{
        'msg:running': _job(
          messageId: 'msg:running',
          status: 'running',
          attemptId: 11,
        ),
      },
    );
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    final applied = await store.completeFollowupIfCurrentAttempt(
      messageId: 'msg:running',
      expectedAttemptId: 11,
      todoId: 'todo-1',
      todoTitle: 'Todo',
      newStatus: null,
      dueAtMs: 12345,
      nowMs: 1000,
    );

    expect(applied, isTrue);
    expect(backend.completeFollowupCalls, 1);
    expect(backend.lastNewStatus, isNull);
    expect(backend.lastDueAtMs, 12345);
    expect(backend.updateTodoDueCalls, 0);
  });
}

SemanticParseJob _job({
  required String messageId,
  required String status,
  required int attemptId,
}) {
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
    suggestedTags: null,
    suggestedTagConfidence: null,
    tagSuggestionState: null,
    appliedTagIds: null,
    undoneAtMs: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

final class _ThrowingClaimBackend extends AppBackend
    implements SemanticParseAttemptAwareBackend {
  _ThrowingClaimBackend({
    required this.thrownError,
    required this.jobsByMessageId,
  });

  final Object thrownError;
  final Map<String, SemanticParseJob> jobsByMessageId;

  @override
  Future<int?> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    throw thrownError;
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    return messageIds
        .map((id) => jobsByMessageId[id])
        .whereType<SemanticParseJob>()
        .toList(growable: false);
  }

  @override
  Future<bool> markSemanticParseJobFailedIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async =>
      false;

  @override
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
  }) async =>
      false;

  @override
  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async =>
      false;

  @override
  Future<List<String>?> completeSemanticParseNoActionIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async =>
      null;

  @override
  Future<bool> completeSemanticParseCreateIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    required String status,
    int? dueAtMs,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
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
      false;

  @override
  Future<bool> completeSemanticParseFollowupIfCurrentAttempt(
    Uint8List key, {
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
  }) async =>
      false;

  @override
  Future<List<String>> applySemanticParseTagsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required List<String> suggestedTags,
  }) async =>
      const <String>[];

  @override
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
  }) async =>
      null;

  @override
  Future<void> upsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {}

  @override
  Future<String?> setTodoStatusFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String newStatus,
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NonAttemptAwareBackend extends AppBackend {
  _NonAttemptAwareBackend({required this.jobsByMessageId});

  final Map<String, SemanticParseJob> jobsByMessageId;

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    return messageIds
        .map((id) => jobsByMessageId[id])
        .whereType<SemanticParseJob>()
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AtomicFollowupBackend extends AppBackend
    implements SemanticParseAttemptAwareBackend {
  _AtomicFollowupBackend({required this.jobsByMessageId});

  final Map<String, SemanticParseJob> jobsByMessageId;
  int completeFollowupCalls = 0;
  int updateTodoDueCalls = 0;
  String? lastNewStatus;
  int? lastDueAtMs;

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    return messageIds
        .map((id) => jobsByMessageId[id])
        .whereType<SemanticParseJob>()
        .toList(growable: false);
  }

  @override
  Future<bool> completeSemanticParseFollowupIfCurrentAttempt(
    Uint8List key, {
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
    completeFollowupCalls += 1;
    lastNewStatus = newStatus;
    lastDueAtMs = dueAtMs;
    return true;
  }

  @override
  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) async {
    updateTodoDueCalls += 1;
    throw UnimplementedError();
  }

  @override
  Future<int?> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async =>
      null;

  @override
  Future<bool> markSemanticParseJobFailedIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async =>
      false;

  @override
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
  }) async =>
      false;

  @override
  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async =>
      false;

  @override
  Future<List<String>?> completeSemanticParseNoActionIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async =>
      null;

  @override
  Future<bool> completeSemanticParseCreateIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    required String status,
    int? dueAtMs,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
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
      false;

  @override
  Future<List<String>> applySemanticParseTagsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required List<String> suggestedTags,
  }) async =>
      const <String>[];

  @override
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
  }) async =>
      null;

  @override
  Future<void> upsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {}

  @override
  Future<String?> setTodoStatusFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String newStatus,
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
