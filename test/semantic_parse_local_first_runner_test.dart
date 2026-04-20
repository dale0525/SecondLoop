import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('runner skips enhancement when local parse is high confidence',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:1',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:1': '明天下午 3 点提交材料'},
    );
    final client = _FakeClient();

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 0);
    expect(client.parseRequests, 0);
    expect(store.createdTodoIds, contains('todo:msg:1'));
  });

  test('runner skips enhancement for unambiguous local followup', () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:local_followup',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:local_followup': '把报销改到明天'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );
    final client = _FakeClient();

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 0);
    expect(client.parseRequests, 0);
    expect(store.updatedStatusByTodoId, isEmpty);
    expect(store.updatedDueByTodoId['todo:1'], isNotNull);
  });

  test('runner uses retrieved semantic candidates to resolve followup locally',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:semantic_followup',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:semantic_followup': '把这个完成'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访客户', status: 'open'),
      ],
    );
    final client = _FakeClient(
      retrievedTodoCandidateIds: const <String>['todo:2'],
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 0);
    expect(store.updatedStatusByTodoId['todo:2'], 'done');
  });

  test(
      'runner retrieves semantic candidates for deictic followup edits with no lexical match',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:deictic_edit',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:deictic_edit': 'move this to tomorrow'
      },
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(
          id: 'todo:1',
          title: 'expense report',
          status: 'open',
        ),
        SemanticParseTodoCandidate(
          id: 'todo:2',
          title: 'client followup',
          status: 'open',
        ),
      ],
    );
    final client = _FakeClient(
      retrievedTodoCandidateIds: const <String>['todo:2'],
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'en-US',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 1);
    expect(client.parseRequests, 0);
    expect(store.updatedDueByTodoId['todo:2'], isNotNull);
  });

  test(
      'runner retrieves semantic candidates for zh deictic holiday followup with a single open todo',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:zh_deictic_holiday_single',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:zh_deictic_holiday_single': '把这个改到年初一之后第一个工作日',
      },
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(
          id: 'todo:1',
          title: '提交材料',
          status: 'open',
        ),
      ],
    );
    final client = _FakeClient(
      retrievedTodoCandidateIds: const <String>['todo:1'],
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 4, 20, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 1);
    expect(client.parseRequests, 0);
    expect(
      store.updatedDueByTodoId['todo:1'],
      DateTime.parse('2027-02-15T21:00:00+08:00').millisecondsSinceEpoch,
    );
  });

  test(
      'runner retrieves semantic candidates for zh deictic status followup with a single open todo',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:zh_deictic_status_single',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:zh_deictic_status_single': '把这个完成',
      },
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(
          id: 'todo:1',
          title: '提交材料',
          status: 'open',
        ),
      ],
    );
    final client = _FakeClient(
      retrievedTodoCandidateIds: const <String>['todo:1'],
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 4, 20, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 1);
    expect(client.parseRequests, 0);
    expect(store.updatedStatusByTodoId['todo:1'], 'done');
  });

  test(
      'runner treats multiple retrieved semantic candidate ids as ambiguous order-only hints',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:semantic_ambiguous',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:semantic_ambiguous': '把这个完成'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访客户', status: 'open'),
      ],
    );
    final client = _FakeClient(
      retrievedTodoCandidateIds: const <String>['todo:1', 'todo:2'],
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:2","new_status":"done","due_local_iso":null}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 1);
    expect(client.lastLocalResultJson,
        contains('"local_intent":"ambiguous_followup"'));
    expect(client.lastUnresolvedFields, contains('todo_id'));
    expect(client.lastUnresolvedFields, contains('new_status'));
    expect(store.updatedStatusByTodoId['todo:2'], 'done');
  });

  test('runner requests enhancement when local parse is ambiguous', () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:2',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:2': '把这个改到节后第一个工作日'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:1","new_status":null,"due_local_iso":"2026-02-24T21:00:00"}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 1);
    expect(client.lastLocalResultJson,
        contains('"local_intent":"ambiguous_followup"'));
    expect(client.lastUnresolvedFields, contains('todo_id'));
    expect(client.lastUnresolvedFields, contains('due_local_iso'));
    expect(store.updatedDueByTodoId['todo:1'], isNotNull);
  });

  test(
      'runner does not mark optional due field unresolved for status-only ambiguity',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:status_only_ambiguity',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:status_only_ambiguity': '把这个完成'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:1","new_status":"done","due_local_iso":null}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 1);
    expect(client.lastUnresolvedFields, contains('todo_id'));
    expect(client.lastUnresolvedFields, contains('new_status'));
    expect(client.lastUnresolvedFields, isNot(contains('due_local_iso')));
  });

  test('runner marks out-of-range zh-CN holiday phrases as enhancement-needed',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:3',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:3': '把这个改到节后第一个工作日'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:1","new_status":null,"due_local_iso":"2031-02-05T21:00:00"}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2031, 1, 20, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 1);
    expect(client.lastLocalResultJson,
        contains('"local_intent":"needs_enhancement"'));
    expect(client.lastUnresolvedFields, contains('due_local_iso'));
    expect(store.updatedDueByTodoId['todo:1'], isNotNull);
  });

  test(
      'runner preserves todo disambiguation when out-of-range holiday phrases need enhancement',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:out_of_range_ambiguous',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:out_of_range_ambiguous': '把这个改到节后第一个工作日',
      },
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:2","new_status":null,"due_local_iso":"2031-02-05T21:00:00"}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2031, 1, 20, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.retrieveRequests, 1);
    expect(client.parseRequests, 1);
    expect(client.lastLocalResultJson,
        contains('"local_intent":"ambiguous_followup"'));
    expect(client.lastUnresolvedFields, contains('todo_id'));
    expect(client.lastUnresolvedFields, contains('due_local_iso'));
    expect(store.updatedDueByTodoId['todo:2'], isNotNull);
  });

  test('runner ignores enhancement followup ids outside candidate set',
      () async {
    final store = _FakeStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:4',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:4': '把这个改到节后第一个工作日'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":0.91,"todo_id":"todo:missing","new_status":null,"due_local_iso":"2026-02-24T21:00:00"}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 0);
    expect(store.updatedStatusByTodoId, isEmpty);
    expect(store.updatedDueByTodoId, isEmpty);
  });
}

final class _FakeStore implements SemanticParseAutoActionsStore {
  _FakeStore({
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
  }) {
    return SemanticParseJob(
      messageId: messageId,
      status: status,
      attemptId: attemptId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
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
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
    );
  }
}

final class _FakeClient implements SemanticParseAutoActionsClient {
  _FakeClient({
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
