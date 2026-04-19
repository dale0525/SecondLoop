import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

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

  test('runner passes recurrence rule json to store for create decision',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:recurring',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:recurring': '每周提交周报'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"提交周报","status":"open","due_local_iso":"2026-02-04T09:00:00","recurrence":{"freq":"weekly","interval":1}}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.95,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 3, 12, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(store.lastRecurrenceRuleJson, '{"freq":"weekly","interval":1}');
  });

  test('runner stores checklist suggestions for created todo', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:checklist',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:checklist': 'Plan launch'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"Plan launch","status":"open","due_local_iso":null}',
      checklistSuggestions: const <String>[
        'Draft launch post',
        'Share with team'
      ],
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
    expect(store.generatedChecklistSuggestionsByTodoId['todo:msg:checklist'],
        const <String>['Draft launch post', 'Share with team']);
    expect(client.lastChecklistStatus, 'open');
    expect(client.lastChecklistDueAtMs, isNull);
  });

  test('runner sends local result and unresolved fields to enhancement path',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:enhance',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:enhance': '把这个改到节后第一个工作日'},
      openCandidates: const <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '回访', status: 'open'),
      ],
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":1.0,"todo_id":"todo:1","new_status":null,"due_local_iso":"2026-02-24T21:00:00"}',
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.86,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 4, 10, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.lastLocalResultJson,
        contains('"local_intent":"ambiguous_followup"'));
    expect(client.lastUnresolvedFields, contains('todo_id'));
    expect(client.lastUnresolvedFields, contains('due_local_iso'));
  });

  test('runner cancels when message is deleted during remote parse', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:deleted_mid_run',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:deleted_mid_run': '买牛奶'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"买牛奶","status":"inbox","suggested_tags":["Errand"],"tag_confidence":0.95}',
      onParseMessageAction: () async {
        store.deleteMessage('msg:deleted_mid_run');
      },
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(result.didUpdateJobs, isTrue);
    expect(store.createdTodoIds, isEmpty);
    expect(store.updatedStatusByTodoId, isEmpty);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded, isNull);
    expect(store.canceledMessageIds, contains('msg:deleted_mid_run'));
  });

  test('runner cancels when message analysis changes during remote parse',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:edited_mid_run',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:edited_mid_run': '买牛奶'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"买牛奶","status":"inbox","suggested_tags":["Errand"],"tag_confidence":0.95}',
      onParseMessageAction: () async {
        store.updateMessage(
          'msg:edited_mid_run',
          const SemanticParseMessageInput(
            sourceText: '明天下午开会',
            analysisText: '明天下午开会',
            allowCreate: true,
          ),
        );
      },
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(result.didUpdateJobs, isTrue);
    expect(store.createdTodoIds, isEmpty);
    expect(store.updatedStatusByTodoId, isEmpty);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded, isNull);
    expect(store.canceledMessageIds, contains('msg:edited_mid_run'));
  });

  test('runner ignores late success after job is retried mid-run', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:retried_mid_run',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:retried_mid_run': '买牛奶'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"买牛奶","status":"inbox","suggested_tags":["Errand"],"tag_confidence":0.95}',
      onParseMessageAction: () async {
        store.requeueJob('msg:retried_mid_run', nowMs: 2000);
        store.markRunningAttempt('msg:retried_mid_run', nowMs: 2001);
      },
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(result.didUpdateJobs, isTrue);
    expect(store.createdTodoIds, isEmpty);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded, isNull);
    expect(store.lastFailed, isNull);
    expect(store.currentJobStatus('msg:retried_mid_run'), 'running');
    expect(store.currentJobUpdatedAtMs('msg:retried_mid_run'), 2001);
  });

  test('runner does not count processed when finalize loses attempt race',
      () async {
    late _FakeStore store;
    store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:finalize_race',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:finalize_race': '买牛奶'},
      beforeMarkSucceededIfCurrentAttempt: (
        String messageId,
        int expectedAttemptId,
        int nowMs,
      ) {
        store.requeueJob(messageId, nowMs: nowMs + 1);
        store.markRunningAttempt(messageId, nowMs: nowMs + 2);
      },
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"买牛奶","status":"inbox"}',
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

    expect(result.processed, 0);
    expect(store.createdTodoIds, isEmpty);
    expect(store.lastSucceeded, isNull);
    expect(store.currentJobStatus('msg:finalize_race'), 'running');
    expect(store.currentJobUpdatedAtMs('msg:finalize_race'), 1002);
  });

  test('runner skips stale claim conflict and continues later jobs', () async {
    final store = _FakeStore(
      jobs: const [
        SemanticParseAutoActionJob(
          messageId: 'msg:claim_conflict',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
        SemanticParseAutoActionJob(
          messageId: 'msg:after_conflict',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 1,
        ),
      ],
      messages: const {
        'msg:claim_conflict': 'ignored',
        'msg:after_conflict': '买牛奶',
      },
      claimConflictMessageIds: const {'msg:claim_conflict'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"买牛奶","status":"inbox","due_local_iso":null}',
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
    expect(result.didMutateAny, isTrue);
    expect(result.didUpdateJobs, isTrue);
    expect(store.createdTodoIds, contains('todo:msg:after_conflict'));
    expect(store.lastFailed, isNull);
    expect(store.lastSucceeded?.messageId, 'msg:after_conflict');
  });

  test('runner ignores late failure after job is retried mid-run', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:retried_fail_mid_run',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:retried_fail_mid_run': '买牛奶'},
    );
    final client = _FakeClient(
      error: TimeoutException('timed out'),
      onParseMessageAction: () async {
        store.requeueJob('msg:retried_fail_mid_run', nowMs: 2000);
        store.markRunningAttempt('msg:retried_fail_mid_run', nowMs: 2001);
      },
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(result.didUpdateJobs, isTrue);
    expect(store.createdTodoIds, isEmpty);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded, isNull);
    expect(store.lastFailed, isNull);
    expect(store.currentJobStatus('msg:retried_fail_mid_run'), 'running');
    expect(store.currentJobUpdatedAtMs('msg:retried_fail_mid_run'), 2001);
  });

  test('runner processes running jobs (crash recovery)', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:3',
          status: 'running',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:3': '修电视机'},
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
    expect(store.createdTodoIds, contains('todo:msg:3'));
    expect(store.lastSucceeded?.appliedActionKind, 'create');
  });

  test('runner passes task_type hint to store for create decision', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:task_type',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:task_type': '调研一下当前主流的 llm 模型'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"调研一下当前主流的 llm 模型","status":"inbox","task_type":"research","due_local_iso":null}',
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
    expect(store.lastFollowupTaskTypeHint, 'research');
  });

  test('runner records the actual applied todo id from store', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:custom',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:custom': '更新事项内容'},
      upsertTodoResultByMessageId: const {'msg:custom': 'legacy:todo:42'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"更新事项内容","status":"open","due_local_iso":"2026-02-04T09:00:00"}',
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
    expect(store.lastSucceeded?.appliedActionKind, 'create');
    expect(store.lastSucceeded?.appliedTodoId, 'legacy:todo:42');
  });

  test('runner falls back to local resolver when client throws', () async {
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
      messages: {'msg:2': '明天 3pm 提交材料'},
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
      morningMinutes: 9 * 60,
      firstDayOfWeekIndex: 1,
    );

    expect(result.processed, 1);
    expect(store.createdTodoIds, contains('todo:msg:2'));
    expect(store.lastFailed, isNull);
    expect(store.lastSucceeded?.appliedActionKind, 'create');
  });

  test('runner retries instead of local fallback when parse is interrupted',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:interrupted',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:interrupted': '明天提醒我提交材料'},
    );
    final client = _FakeClient(
      error: StateError('operation canceled because app entered background'),
    );

    final runner = SemanticParseAutoActionsRunner(
      store: store,
      client: client,
      settings: const SemanticParseAutoActionsRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        minAutoConfidence: 0.95,
      ),
      nowMs: () => 1000,
      nowLocal: () => DateTime(2026, 2, 3, 12, 0, 0),
    );

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
      morningMinutes: 9 * 60,
      firstDayOfWeekIndex: 1,
    );

    expect(result.processed, 0);
    expect(store.lastSucceeded, isNull);
    expect(store.lastFailed, isNotNull);
    expect(store.lastFailed?.attempts, 1);
    expect(store.lastFailed?.nextRetryAtMs, 31000);
    expect(store.createdTodoIds, isEmpty);
  });

  test('runner marks none when create is disallowed for the message input',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:create_blocked',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const {},
      messageInputs: const {
        'msg:create_blocked': SemanticParseMessageInput(
          sourceText:
              'This is a very long source note that should not create a todo automatically.',
          analysisText: 'tomorrow send the recap',
          allowCreate: false,
        ),
      },
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"create","confidence":1.0,"title":"send the recap","status":"inbox","due_local_iso":null}',
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
      localeTag: 'en-US',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 0);
    expect(store.createdTodoIds, isEmpty);
    expect(store.lastSucceeded?.appliedActionKind, 'none');
  });

  test('runner still allows followup when create is disallowed', () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:followup_allowed',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const {},
      messageInputs: const {
        'msg:followup_allowed': SemanticParseMessageInput(
          sourceText:
              'This is an attachment-driven message context that should only link to existing tasks.',
          analysisText: 'mark it done',
          allowCreate: false,
        ),
      },
      openCandidates: const [
        SemanticParseTodoCandidate(
          id: 'todo:existing',
          title: 'Prepare project recap',
          status: 'open',
        ),
      ],
      previousStatusByTodoId: const {'todo:existing': 'open'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"followup","confidence":1.0,"todo_id":"todo:existing","new_status":"done"}',
      candidateTodoIds: const ['todo:existing'],
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
      localeTag: 'en-US',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(store.createdTodoIds, isEmpty);
    expect(store.updatedStatusByTodoId['todo:existing'], 'done');
    expect(store.lastSucceeded?.appliedActionKind, 'followup');
  });

  test('runner auto-applies semantic tags when tag confidence is high',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:tag_only',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:tag_only': '今天把报销单整理完了'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"none","confidence":0.2,"suggested_tags":["work","Finance","work"],"tag_confidence":0.96}',
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isTrue);
    expect(store.appliedSemanticTagsByMessage['msg:tag_only'],
        equals(const <String>['work', 'finance']));
    expect(store.lastSucceeded?.appliedActionKind, 'none');
    expect(
      store.lastSucceeded?.suggestedTags,
      equals(const <String>['work', 'finance']),
    );
    expect(store.lastSucceeded?.suggestedTagConfidence, 0.96);
    expect(store.lastSucceeded?.tagSuggestionState, 'applied');
    expect(
      store.lastSucceeded?.appliedTagIds,
      equals(const <String>['tag:work', 'tag:finance']),
    );
  });

  test('runner auto-applies semantic tags at 0.8 confidence by default',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:tag_08',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:tag_08': '整理这周的报销和预算'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"none","confidence":0.8,"suggested_tags":["Finance","work"]}',
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isTrue);
    expect(store.appliedSemanticTagsByMessage['msg:tag_08'],
        equals(const <String>['finance', 'work']));
    expect(store.lastSucceeded?.appliedActionKind, 'none');
    expect(
      store.lastSucceeded?.suggestedTags,
      equals(const <String>['finance', 'work']),
    );
    expect(store.lastSucceeded?.suggestedTagConfidence, 0.8);
    expect(store.lastSucceeded?.tagSuggestionState, 'applied');
    expect(
      store.lastSucceeded?.appliedTagIds,
      equals(const <String>['tag:finance', 'tag:work']),
    );
  });

  test('runner stores pending semantic tag suggestions for medium confidence',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:tag_pending',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:tag_pending': '整理会议纪要并归档'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"none","confidence":0.2,"suggested_tags":["Work","finance","work"],"tag_confidence":0.72}',
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded?.appliedActionKind, 'none');
    expect(
      store.lastSucceeded?.suggestedTags,
      equals(const <String>['work', 'finance']),
    );
    expect(store.lastSucceeded?.suggestedTagConfidence, 0.72);
    expect(store.lastSucceeded?.tagSuggestionState, 'pending');
    expect(store.lastSucceeded?.appliedTagIds, isNull);
  });

  test('runner hides semantic tag suggestion when confidence is too low',
      () async {
    final store = _FakeStore(
      jobs: [
        const SemanticParseAutoActionJob(
          messageId: 'msg:tag_low',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: {'msg:tag_low': '聊一下周末安排'},
    );
    final client = _FakeClient(
      responseJson:
          '{"kind":"none","confidence":0.2,"suggested_tags":["life","travel"],"tag_confidence":0.42}',
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(store.appliedSemanticTagsByMessage, isEmpty);
    expect(store.lastSucceeded?.appliedActionKind, 'none');
    expect(store.lastSucceeded?.suggestedTags, isNull);
    expect(store.lastSucceeded?.suggestedTagConfidence, isNull);
    expect(store.lastSucceeded?.tagSuggestionState, 'none');
    expect(store.lastSucceeded?.appliedTagIds, isNull);
  });
}

final class _FakeStore implements SemanticParseAutoActionsStore {
  _FakeStore({
    required List<SemanticParseAutoActionJob> jobs,
    required Map<String, String> messages,
    Map<String, SemanticParseMessageInput>? messageInputs,
    List<SemanticParseTodoCandidate> openCandidates =
        const <SemanticParseTodoCandidate>[],
    Map<String, String> previousStatusByTodoId = const <String, String>{},
    Map<String, String>? upsertTodoResultByMessageId,
    Set<String> claimConflictMessageIds = const <String>{},
    this.beforeMarkSucceededIfCurrentAttempt,
  })  : _jobs = List<SemanticParseAutoActionJob>.from(jobs),
        _messages = Map<String, String>.from(messages),
        _messageInputs = Map<String, SemanticParseMessageInput>.from(
          messageInputs ?? const <String, SemanticParseMessageInput>{},
        ),
        _openCandidates = List<SemanticParseTodoCandidate>.from(openCandidates),
        _previousStatusByTodoId =
            Map<String, String>.from(previousStatusByTodoId),
        _upsertTodoResultByMessageId =
            Map<String, String>.from(upsertTodoResultByMessageId ?? const {}),
        _claimConflictMessageIds = Set<String>.from(claimConflictMessageIds);

  final List<SemanticParseAutoActionJob> _jobs;
  final Map<String, String> _messages;
  final Map<String, SemanticParseMessageInput> _messageInputs;
  final List<SemanticParseTodoCandidate> _openCandidates;
  final Map<String, String> _previousStatusByTodoId;
  final Map<String, String> _upsertTodoResultByMessageId;
  final Set<String> _claimConflictMessageIds;
  void Function(String messageId, int expectedAttemptId, int nowMs)?
      beforeMarkSucceededIfCurrentAttempt;

  final List<String> createdTodoIds = <String>[];
  final List<String> canceledMessageIds = <String>[];
  final Map<String, String> updatedStatusByTodoId = <String, String>{};
  final Map<String, List<String>> appliedSemanticTagsByMessage =
      <String, List<String>>{};
  SemanticParseJobSucceededArgs? lastSucceeded;
  SemanticParseJobFailedArgs? lastFailed;
  final Map<String, List<String>> generatedChecklistSuggestionsByTodoId =
      <String, List<String>>{};
  String? lastRecurrenceRuleJson;
  String? lastFollowupTaskTypeHint;
  final Map<String, SemanticParseJob> _currentJobs =
      <String, SemanticParseJob>{};

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return _jobs.take(limit).toList(growable: false);
  }

  @override
  Future<SemanticParseJob?> getJob(String messageId) async {
    return _currentJobs[messageId];
  }

  @override
  Future<SemanticParseMessageInput?> getMessageInput(String messageId) async {
    final predefined = _messageInputs[messageId];
    if (predefined != null) return predefined;

    final sourceText = _messages[messageId];
    if (sourceText == null) return null;
    return SemanticParseMessageInput(
      sourceText: sourceText,
      analysisText: sourceText,
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
    if (_claimConflictMessageIds.contains(messageId)) {
      return null;
    }
    return markRunningAttempt(messageId, nowMs: nowMs);
  }

  @override
  Future<bool> markJobSucceededIfCurrentAttempt(
    SemanticParseJobSucceededArgs args, {
    required int expectedAttemptId,
  }) async {
    beforeMarkSucceededIfCurrentAttempt?.call(
      args.messageId,
      expectedAttemptId,
      args.nowMs,
    );
    final current = _currentJobs[args.messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    lastSucceeded = args;
    _currentJobs[args.messageId] = _buildJob(
      messageId: args.messageId,
      status: 'succeeded',
      attemptId: expectedAttemptId,
      updatedAtMs: args.nowMs,
    );
    return true;
  }

  @override
  Future<bool> markJobFailedIfCurrentAttempt(
    SemanticParseJobFailedArgs args, {
    required int expectedAttemptId,
  }) async {
    final current = _currentJobs[args.messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    lastFailed = args;
    _currentJobs[args.messageId] = _buildJob(
      messageId: args.messageId,
      status: 'failed',
      attemptId: expectedAttemptId,
      updatedAtMs: args.nowMs,
    );
    return true;
  }

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {
    canceledMessageIds.add(messageId);
    final currentAttemptId = _currentJobs[messageId]?.attemptId.toInt() ?? 0;
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'canceled',
      attemptId: currentAttemptId,
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<bool> markJobCanceledIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    final current = _currentJobs[messageId];
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
    beforeMarkSucceededIfCurrentAttempt?.call(
      messageId,
      expectedAttemptId,
      nowMs,
    );
    final current = _currentJobs[messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return null;
    }

    List<String> appliedTagIds = const <String>[];
    List<String>? suggestedTags;
    double? tagConfidence;
    String tagSuggestionState = 'none';
    if (autoApplySuggestedTags != null && autoApplySuggestedTags.isNotEmpty) {
      final result = await applySemanticTags(
        messageId: messageId,
        suggestedTags: autoApplySuggestedTags,
        expectedAttemptId: expectedAttemptId,
      );
      if (result.appliedTagIds.isNotEmpty) {
        appliedTagIds = result.appliedTagIds;
        suggestedTags = autoApplySuggestedTags;
        tagConfidence = suggestedTagConfidence;
        tagSuggestionState = 'applied';
      }
    } else if (pendingSuggestedTags != null &&
        pendingSuggestedTags.isNotEmpty) {
      suggestedTags = pendingSuggestedTags;
      tagConfidence = suggestedTagConfidence;
      tagSuggestionState = 'pending';
    }

    lastSucceeded = SemanticParseJobSucceededArgs(
      messageId: messageId,
      appliedActionKind: 'none',
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: tagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds.isEmpty ? null : appliedTagIds,
      nowMs: nowMs,
    );
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'succeeded',
      attemptId: expectedAttemptId,
      updatedAtMs: nowMs,
    );
    return appliedTagIds;
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
    beforeMarkSucceededIfCurrentAttempt?.call(
      messageId,
      expectedAttemptId,
      nowMs,
    );
    final current = _currentJobs[messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }

    List<String> appliedTagIds = const <String>[];
    List<String>? suggestedTags;
    double? tagConfidence;
    String tagSuggestionState = 'none';
    if (autoApplySuggestedTags != null && autoApplySuggestedTags.isNotEmpty) {
      final result = await applySemanticTags(
        messageId: messageId,
        suggestedTags: autoApplySuggestedTags,
        expectedAttemptId: expectedAttemptId,
      );
      if (result.appliedTagIds.isNotEmpty) {
        appliedTagIds = result.appliedTagIds;
        suggestedTags = autoApplySuggestedTags;
        tagConfidence = suggestedTagConfidence;
        tagSuggestionState = 'applied';
      }
    } else if (pendingSuggestedTags != null &&
        pendingSuggestedTags.isNotEmpty) {
      suggestedTags = pendingSuggestedTags;
      tagConfidence = suggestedTagConfidence;
      tagSuggestionState = 'pending';
    }

    final todoId = _upsertTodoResultByMessageId[messageId] ?? 'todo:$messageId';
    createdTodoIds.add(todoId);
    lastRecurrenceRuleJson = recurrenceRuleJson;
    lastFollowupTaskTypeHint = followupTaskTypeHint;
    if (checklistSuggestions.isNotEmpty) {
      generatedChecklistSuggestionsByTodoId[todoId] =
          List<String>.from(checklistSuggestions);
    }
    lastSucceeded = SemanticParseJobSucceededArgs(
      messageId: messageId,
      appliedActionKind: 'create',
      appliedTodoId: todoId,
      appliedTodoTitle: title,
      appliedPrevTodoStatus: null,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: tagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds.isEmpty ? null : appliedTagIds,
      nowMs: nowMs,
    );
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'succeeded',
      attemptId: expectedAttemptId,
      updatedAtMs: nowMs,
    );
    return true;
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
    beforeMarkSucceededIfCurrentAttempt?.call(
      messageId,
      expectedAttemptId,
      nowMs,
    );
    final current = _currentJobs[messageId];
    if (current == null || current.attemptId.toInt() != expectedAttemptId) {
      return false;
    }

    List<String> appliedTagIds = const <String>[];
    List<String>? suggestedTags;
    double? tagConfidence;
    String tagSuggestionState = 'none';
    if (autoApplySuggestedTags != null && autoApplySuggestedTags.isNotEmpty) {
      final result = await applySemanticTags(
        messageId: messageId,
        suggestedTags: autoApplySuggestedTags,
        expectedAttemptId: expectedAttemptId,
      );
      if (result.appliedTagIds.isNotEmpty) {
        appliedTagIds = result.appliedTagIds;
        suggestedTags = autoApplySuggestedTags;
        tagConfidence = suggestedTagConfidence;
        tagSuggestionState = 'applied';
      }
    } else if (pendingSuggestedTags != null &&
        pendingSuggestedTags.isNotEmpty) {
      suggestedTags = pendingSuggestedTags;
      tagConfidence = suggestedTagConfidence;
      tagSuggestionState = 'pending';
    }

    final previousStatus = _previousStatusByTodoId[todoId];
    if (newStatus != null) {
      updatedStatusByTodoId[todoId] = newStatus;
    }
    lastSucceeded = SemanticParseJobSucceededArgs(
      messageId: messageId,
      appliedActionKind: 'followup',
      appliedTodoId: todoId,
      appliedTodoTitle: todoTitle,
      appliedPrevTodoStatus: previousStatus,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: tagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds.isEmpty ? null : appliedTagIds,
      nowMs: nowMs,
    );
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'succeeded',
      attemptId: expectedAttemptId,
      updatedAtMs: nowMs,
    );
    return true;
  }

  void deleteMessage(String messageId) {
    _messages.remove(messageId);
    _messageInputs.remove(messageId);
  }

  void updateMessage(String messageId, SemanticParseMessageInput input) {
    _messages[messageId] = input.sourceText;
    _messageInputs[messageId] = input;
  }

  void requeueJob(String messageId, {required int nowMs}) {
    final currentAttemptId = _currentJobs[messageId]?.attemptId.toInt() ?? 0;
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'pending',
      attemptId: currentAttemptId,
      updatedAtMs: nowMs,
    );
  }

  int markRunningAttempt(String messageId, {required int nowMs}) {
    final nextAttemptId = (_currentJobs[messageId]?.attemptId.toInt() ?? 0) + 1;
    _currentJobs[messageId] = _buildJob(
      messageId: messageId,
      status: 'running',
      attemptId: nextAttemptId,
      updatedAtMs: nowMs,
    );
    return nextAttemptId;
  }

  String? currentJobStatus(String messageId) => _currentJobs[messageId]?.status;

  int? currentJobUpdatedAtMs(String messageId) =>
      _currentJobs[messageId]?.updatedAtMs.toInt();

  SemanticParseJob _buildJob({
    required String messageId,
    required String status,
    required int attemptId,
    required int updatedAtMs,
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
      updatedAtMs: PlatformInt64Util.from(updatedAtMs),
    );
  }

  @override
  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
    int? expectedAttemptId,
  }) async {
    final current = _currentJobs[messageId];
    if (expectedAttemptId != null &&
        (current == null || current.attemptId.toInt() != expectedAttemptId)) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }
    final deduped = <String>[];
    final seen = <String>{};
    for (final raw in suggestedTags) {
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      deduped.add(normalized);
    }
    if (deduped.isEmpty) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }

    appliedSemanticTagsByMessage[messageId] = deduped;
    final tagIds =
        deduped.map((tagName) => 'tag:$tagName').toList(growable: false);
    return SemanticParseTagApplyResult(
      appliedCount: deduped.length,
      appliedTagIds: tagIds,
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
    final current = _currentJobs[messageId];
    if (expectedAttemptId != null &&
        (current == null || current.attemptId.toInt() != expectedAttemptId)) {
      return null;
    }
    final todoId = _upsertTodoResultByMessageId[messageId] ?? 'todo:$messageId';
    createdTodoIds.add(todoId);
    lastRecurrenceRuleJson = recurrenceRuleJson;
    lastFollowupTaskTypeHint = followupTaskTypeHint;
    return todoId;
  }

  @override
  Future<void> upsertGeneratedChecklistSuggestions({
    required String messageId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
    int? expectedAttemptId,
  }) async {
    final current = _currentJobs[messageId];
    if (expectedAttemptId != null &&
        (current == null || current.attemptId.toInt() != expectedAttemptId)) {
      return;
    }
    generatedChecklistSuggestionsByTodoId[todoId] =
        List<String>.from(suggestions);
  }

  @override
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
    int? expectedAttemptId,
  }) async {
    final current = _currentJobs[messageId];
    if (expectedAttemptId != null &&
        (current == null || current.attemptId.toInt() != expectedAttemptId)) {
      return null;
    }
    updatedStatusByTodoId[todoId] = newStatus;
    return _previousStatusByTodoId[todoId];
  }
}

final class _FakeClient implements SemanticParseAutoActionsClient {
  _FakeClient({
    this.responseJson,
    this.checklistSuggestions,
    this.error,
    this.candidateTodoIds = const <String>[],
    this.onParseMessageAction,
  });

  final String? responseJson;
  final List<String>? checklistSuggestions;
  final Object? error;
  final List<String> candidateTodoIds;
  final Future<void> Function()? onParseMessageAction;
  String? lastChecklistStatus;
  int? lastChecklistDueAtMs;
  String? lastLocalResultJson;
  List<String> lastUnresolvedFields = const <String>[];

  @override
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  }) async {
    if (topK <= 0) return const <String>[];
    return candidateTodoIds.take(topK).toList(growable: false);
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
    if (onParseMessageAction != null) {
      await onParseMessageAction!();
    }
    if (error != null) throw error!;
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
    if (error != null) throw error!;
    lastChecklistStatus = status;
    lastChecklistDueAtMs = dueAtMs;
    return checklistSuggestions ?? const <String>[];
  }
}
