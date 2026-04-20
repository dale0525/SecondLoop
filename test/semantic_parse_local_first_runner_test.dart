import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';

import 'semantic_parse_local_first_runner_test_support.dart';

void main() {
  test('runner skips enhancement when local parse is high confidence',
      () async {
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient();

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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient();

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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
      'runner keeps zh-Hans-CN locale tags compatible with zh-CN holiday rules',
      () async {
    final store = FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:zh_hans_holiday_single',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{
        'msg:zh_hans_holiday_single': '把这个改到年初一之后第一个工作日',
      },
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(
          id: 'todo:1',
          title: '提交材料',
          status: 'open',
        ),
      ],
    );
    final client = FakeSemanticParseClient(
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
      localeTag: 'zh-Hans-CN',
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
    final store = FakeSemanticParseStore(
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
    final client = FakeSemanticParseClient(
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
