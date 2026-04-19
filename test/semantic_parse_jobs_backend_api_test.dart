import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/semantic_parse_attempt_aware_backend.dart';
import 'package:secondloop/core/backend/semantic_parse_enhancement_backend.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/semantic_parse.dart' as rust_semantic;

import 'test_backend.dart';

void main() {
  test('AppBackend exposes semantic parse job APIs', () async {
    final backend = _Backend();
    final AppBackend api = backend;
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await api.enqueueSemanticParseJob(
      key,
      messageId: 'msg:1',
      nowMs: 1,
    );
    await api.listDueSemanticParseJobs(key, nowMs: 1);
    await api.listSemanticParseJobsByMessageIds(key, messageIds: ['msg:1']);
    await api.markSemanticParseJobRunning(key, messageId: 'msg:1', nowMs: 2);
    await api.markSemanticParseJobFailed(
      key,
      messageId: 'msg:1',
      attempts: 1,
      nextRetryAtMs: 100,
      lastError: 'timeout',
      nowMs: 2,
    );
    await api.markSemanticParseJobRetry(key, messageId: 'msg:1', nowMs: 3);
    await api.markSemanticParseJobSucceeded(
      key,
      messageId: 'msg:1',
      appliedActionKind: 'create',
      appliedTodoId: 'todo:msg:1',
      appliedTodoTitle: 'Fix TV',
      appliedPrevTodoStatus: null,
      suggestedTags: const <String>['work', 'finance'],
      suggestedTagConfidence: 0.72,
      tagSuggestionState: 'pending',
      appliedTagIds: const <String>['tag:work'],
      nowMs: 4,
    );
    await api.markSemanticParseJobUndone(key, messageId: 'msg:1', nowMs: 5);
    await api.markSemanticParseJobCanceled(
      key,
      messageId: 'msg:1',
      nowMs: 6,
    );

    expect(backend.calls, isNotEmpty);
    expect(backend.calls.first, 'enqueue');
    expect(backend.lastMarkSucceededArgs, isNotNull);
    expect(
      backend.lastMarkSucceededArgs,
      containsPair('suggestedTags', const <String>['work', 'finance']),
    );
    expect(
      backend.lastMarkSucceededArgs,
      containsPair('suggestedTagConfidence', 0.72),
    );
    expect(
      backend.lastMarkSucceededArgs,
      containsPair('tagSuggestionState', 'pending'),
    );
    expect(
      backend.lastMarkSucceededArgs,
      containsPair('appliedTagIds', const <String>['tag:work']),
    );
  });

  test(
      'small semantic parse interfaces expose enhancement and atomic followup APIs',
      () async {
    final backend = _InterfaceBackend();
    final enhancementApi = backend as SemanticParseEnhancementBackend;
    final attemptAwareApi = backend as SemanticParseAttemptAwareBackend;
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await enhancementApi.semanticParseMessageActionEnhancement(
      key,
      text: '把这个改到节后第一个工作日',
      nowLocalIso: '2026-02-04T10:00:00',
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
      localResultJson:
          '{"kind":"none","confidence":0.45,"resolver":"local","diagnostics":{"local_intent":"ambiguous_followup"}}',
      unresolvedFields: const <String>['todo_id', 'due_local_iso'],
      candidates: const <rust_semantic.TodoCandidate>[],
    );
    await attemptAwareApi.completeSemanticParseFollowupIfCurrentAttempt(
      key,
      messageId: 'msg:1',
      expectedAttemptId: 2,
      todoId: 'todo:1',
      todoTitle: '报销',
      newStatus: null,
      dueAtMs: 12345,
      nowMs: 100,
    );

    expect(backend.calls, contains('enhancement'));
    expect(backend.calls, contains('atomicFollowup'));
    expect(backend.lastAtomicFollowupArgs, containsPair('dueAtMs', 12345));
    expect(backend.lastAtomicFollowupArgs, containsPair('newStatus', null));
  });
}

final class _Backend extends TestAppBackend {
  final List<String> calls = <String>[];
  Map<String, Object?>? lastMarkSucceededArgs;

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('enqueue');
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    calls.add('listDue');
    return const <SemanticParseJob>[];
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    calls.add('listByIds');
    return const <SemanticParseJob>[];
  }

  @override
  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('markRunning');
  }

  @override
  Future<void> markSemanticParseJobFailed(
    Uint8List key, {
    required String messageId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    calls.add('markFailed');
  }

  @override
  Future<void> markSemanticParseJobRetry(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('markRetry');
  }

  @override
  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    calls.add('markSucceeded');
    lastMarkSucceededArgs = <String, Object?>{
      'messageId': messageId,
      'appliedActionKind': appliedActionKind,
      'suggestedTags': suggestedTags,
      'suggestedTagConfidence': suggestedTagConfidence,
      'tagSuggestionState': tagSuggestionState,
      'appliedTagIds': appliedTagIds,
      'nowMs': nowMs,
    };
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('markCanceled');
  }

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('markUndone');
  }
}

final class _InterfaceBackend extends TestAppBackend
    implements
        SemanticParseEnhancementBackend,
        SemanticParseAttemptAwareBackend {
  final List<String> calls = <String>[];
  Map<String, Object?>? lastAtomicFollowupArgs;

  @override
  Future<String> semanticParseMessageActionEnhancement(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<rust_semantic.TodoCandidate> candidates,
  }) async {
    calls.add('enhancement');
    return '{"kind":"none","confidence":1.0}';
  }

  @override
  Future<String> semanticParseMessageActionEnhancementCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<rust_semantic.TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    calls.add('enhancementCloud');
    return '{"kind":"none","confidence":1.0}';
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
    calls.add('atomicFollowup');
    lastAtomicFollowupArgs = <String, Object?>{
      'messageId': messageId,
      'todoId': todoId,
      'newStatus': newStatus,
      'dueAtMs': dueAtMs,
      'nowMs': nowMs,
    };
    return true;
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
}
