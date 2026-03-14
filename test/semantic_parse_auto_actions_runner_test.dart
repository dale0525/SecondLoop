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
  })  : _jobs = List<SemanticParseAutoActionJob>.from(jobs),
        _messages = Map<String, String>.from(messages),
        _messageInputs = Map<String, SemanticParseMessageInput>.from(
          messageInputs ?? const <String, SemanticParseMessageInput>{},
        ),
        _openCandidates = List<SemanticParseTodoCandidate>.from(openCandidates),
        _previousStatusByTodoId =
            Map<String, String>.from(previousStatusByTodoId),
        _upsertTodoResultByMessageId =
            Map<String, String>.from(upsertTodoResultByMessageId ?? const {});

  final List<SemanticParseAutoActionJob> _jobs;
  final Map<String, String> _messages;
  final Map<String, SemanticParseMessageInput> _messageInputs;
  final List<SemanticParseTodoCandidate> _openCandidates;
  final Map<String, String> _previousStatusByTodoId;
  final Map<String, String> _upsertTodoResultByMessageId;

  final List<String> createdTodoIds = <String>[];
  final Map<String, String> updatedStatusByTodoId = <String, String>{};
  final Map<String, List<String>> appliedSemanticTagsByMessage =
      <String, List<String>>{};
  SemanticParseJobSucceededArgs? lastSucceeded;
  SemanticParseJobFailedArgs? lastFailed;
  final Map<String, List<String>> generatedChecklistSuggestionsByTodoId =
      <String, List<String>>{};
  String? lastRecurrenceRuleJson;

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return _jobs.take(limit).toList(growable: false);
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
  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
  }) async {
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
  Future<String> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
  }) async {
    final todoId = _upsertTodoResultByMessageId[messageId] ?? 'todo:$messageId';
    createdTodoIds.add(todoId);
    lastRecurrenceRuleJson = recurrenceRuleJson;
    return todoId;
  }

  @override
  Future<void> upsertGeneratedChecklistSuggestions({
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    generatedChecklistSuggestionsByTodoId[todoId] =
        List<String>.from(suggestions);
  }

  @override
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
  }) async {
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
  });

  final String? responseJson;
  final List<String>? checklistSuggestions;
  final Object? error;
  final List<String> candidateTodoIds;

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
    required Duration timeout,
  }) async {
    if (error != null) throw error!;
    return responseJson ?? '{"kind":"none","confidence":0.0}';
  }

  @override
  Future<List<String>> generateChecklistSuggestions({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required Duration timeout,
  }) async {
    if (error != null) throw error!;
    return checklistSuggestions ?? const <String>[];
  }
}
