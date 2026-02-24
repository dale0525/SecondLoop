import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/src/rust/db.dart';

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
