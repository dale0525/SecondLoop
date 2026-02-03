import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';

void main() {
  test('runner auto-creates todo for create decision', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:1',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:1': '修电视机'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"修电视机","status":"inbox","due_local_iso":null}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 3, 12, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(store.createdTodoIds, contains('todo:msg:1'));
    expect(store.lastSucceeded?.appliedActionKind, 'create');
    expect(store.lastSucceeded?.appliedTodoTitle, '修电视机');
  });

  test('runner retries when client throws', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:2',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:2': '修电视机'},
    );
    final client = _FakeClient(error: StateError('boom'));

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 3, 12, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 0);
    expect(store.lastFailed, isNotNull);
    expect(store.lastFailed!.attempts, 1);
    expect(store.lastFailed!.nextRetryAtMs, greaterThan(1000));
  });
}

final class _FakeStore implements SemanticParseAutoActionsStore {
  _FakeStore({
    required List<SemanticParseAutoActionJob> jobs,
    required Map<String, String> messages,
  })  : _jobs = List<SemanticParseAutoActionJob>.from(jobs),
        _messages = Map<String, String>.from(messages);

  final List<SemanticParseAutoActionJob> _jobs;
  final Map<String, String> _messages;

  final List<String> createdTodoIds = <String>[];
  SemanticParseJobSucceededArgs? lastSucceeded;
  SemanticParseJobFailedArgs? lastFailed;

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return _jobs.take(limit).toList(growable: false);
  }

  @override
  Future<String?> getMessageText(String messageId) async {
    return _messages[messageId];
  }

  @override
  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
  }) async {
    return const <SemanticParseTodoCandidate>[];
  }

  @override
  Future<void> markJobRunning({
    required String messageId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobSucceeded(SemanticParseJobSucceededArgs args) async {
    lastSucceeded = args;
  }

  @override
  Future<void> markJobFailed(SemanticParseJobFailedArgs args) async {
    lastFailed = args;
  }

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {}

  @override
  Future<void> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
  }) async {
    createdTodoIds.add('todo:$messageId');
  }

  @override
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
  }) async {
    return null;
  }
}

final class _FakeClient implements SemanticParseAutoActionsClient {
  _FakeClient({this.responseJson, this.error});

  final String? responseJson;
  final Object? error;

  @override
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required Duration timeout,
  }) async {
    if (error != null) throw error!;
    return responseJson ?? '{"kind":"none","confidence":0.0}';
  }
}
