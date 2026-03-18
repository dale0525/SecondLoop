import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/ai/todo_followup_suggestions_ai.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('citation json encoding handles control characters safely', () {
    final jsonText = encodeTodoFollowupCitationsJson(
      const <TodoFollowupCitationDraft>[
        TodoFollowupCitationDraft(
          title: 'Line 1\r\nLine\t2',
          url: 'https://example.com/query?a=1\tb',
          domain: 'example.com',
        ),
      ],
    );

    final parsed = parseTodoFollowupSuggestionJson(
      '{"content":"ok","mode":"web_search","citations":$jsonText}',
    );

    expect(parsed, isNotNull);
    expect(parsed!.citations, hasLength(1));
    expect(parsed.citations.single.title, 'Line 1\r\nLine\t2');
    expect(parsed.citations.single.url, 'https://example.com/query?a=1%09b');
  });

  test('runner generates follow-up for research task', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_research',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_research': Todo(
          id: 'todo_research',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(localeTag: 'zh-CN');

    expect(result.processed, 1);
    expect(store.lastSucceededTodoId, 'todo_research');
    expect(
        store.lastUpsertedSuggestions.single.generationMode, 'model_knowledge');
    expect(client.requestedModes, const <TodoFollowupGenerationMode>[
      TodoFollowupGenerationMode.modelKnowledge,
    ]);
  });

  test('runner generates follow-up for live info lookup task', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_live',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_live': Todo(
          id: 'todo_live',
          title: '去浦东机场接 MU5101',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      supportsWebSearch: true,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.webSearch: const TodoFollowupSuggestionDraft(
          content: '已查询到航站楼、预计到达时间和停车建议。',
          mode: TodoFollowupGenerationMode.webSearch,
          citations: <TodoFollowupCitationDraft>[
            TodoFollowupCitationDraft(
              title: 'Airport',
              url: 'https://example.com/airport',
              domain: 'example.com',
            ),
          ],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(localeTag: 'zh-CN');

    expect(result.processed, 1);
    expect(store.lastUpsertedSuggestions.single.generationMode, 'web_search');
    expect(store.lastUpsertedSuggestions.single.citationsJson,
        contains('example.com'));
    expect(client.requestedModes.first, TodoFollowupGenerationMode.webSearch);
  });

  test('runner skips execution task', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_exec',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_exec': Todo(
          id: 'todo_exec',
          title: '修复登录按钮样式',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(supportsWebSearch: false);

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(localeTag: 'zh-CN');

    expect(result.processed, 1);
    expect(store.lastSkippedTodoId, 'todo_exec');
    expect(store.lastUpsertedSuggestions, isEmpty);
    expect(client.requestedModes, isEmpty);
  });

  test('runner falls back to model knowledge when web search fails', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_compare',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'comparison',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_compare': Todo(
          id: 'todo_compare',
          title: '对比一下 Claude 和 GPT',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      supportsWebSearch: true,
      errorsByMode: <TodoFollowupGenerationMode, Object>{
        TodoFollowupGenerationMode.webSearch: StateError('search unavailable'),
      },
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(client.requestedModes, const <TodoFollowupGenerationMode>[
      TodoFollowupGenerationMode.webSearch,
      TodoFollowupGenerationMode.modelKnowledge,
    ]);
    expect(
        store.lastUpsertedSuggestions.single.generationMode, 'model_knowledge');
  });

  test('runner regenerate includes manual follow-up notes only', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_regen': Todo(
          id: 'todo_regen',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      activitiesByTodoId: const <String, List<TodoActivity>>{
        'todo_regen': <TodoActivity>[
          TodoActivity(
            id: 'a1',
            todoId: 'todo_regen',
            activityType: 'note',
            fromStatus: null,
            toStatus: null,
            content: '用户补充：优先关注价格和 API 稳定性',
            sourceMessageId: null,
            createdAtMs: 0,
          ),
          TodoActivity(
            id: 'a2',
            todoId: 'todo_regen',
            activityType: 'followup_information',
            fromStatus: null,
            toStatus: null,
            content: '旧的自动信息收集结果',
            sourceMessageId: null,
            createdAtMs: 0,
          ),
        ],
      },
      suggestionsByTodoId: const <String, List<TodoFollowupSuggestion>>{
        'todo_regen': <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 's_pending',
            todoId: 'todo_regen',
            content: 'old',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'old',
            citationsJson: null,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        ],
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastDismissedSuggestionIds, const <String>['s_pending']);
    expect(store.pendingSuggestionsFor('todo_regen').single.generationKey,
        'followup:manual_regenerate:research:1000');
    expect(client.lastManualFollowups, const <String>[
      '用户补充：优先关注价格和 API 稳定性',
    ]);
    expect(client.lastTaskContext, isNot(contains('旧的自动信息收集结果')));
  });

  test(
      'runner regenerate keeps deduped pending content and dismisses stale ones',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen_mixed',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_regen_mixed': Todo(
          id: 'todo_regen_mixed',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      suggestionsByTodoId: const <String, List<TodoFollowupSuggestion>>{
        'todo_regen_mixed': <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 's_keep',
            todoId: 'todo_regen_mixed',
            content: '以下内容基于模型知识整理，未联网核实。',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'old_keep',
            citationsJson: null,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
          TodoFollowupSuggestion(
            id: 's_stale',
            todoId: 'todo_regen_mixed',
            content: '旧的待处理建议',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'old_stale',
            citationsJson: null,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        ],
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastDismissedSuggestionIds, const <String>['s_stale']);
    expect(store.pendingSuggestionsFor('todo_regen_mixed'), hasLength(1));
    expect(store.pendingSuggestionsFor('todo_regen_mixed').single.id, 's_keep');
  });

  test('runner manual regenerate ignores stale persisted task type hint',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen_reclassify',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'execution',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_regen_reclassify': Todo(
          id: 'todo_regen_reclassify',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(localeTag: 'zh-CN');

    expect(result.processed, 1);
    expect(store.lastSkippedTodoId, isNull);
    expect(store.lastSucceededTodoId, 'todo_regen_reclassify');
    expect(client.requestedModes, const <TodoFollowupGenerationMode>[
      TodoFollowupGenerationMode.modelKnowledge,
    ]);
  });

  test('runner keeps existing pending suggestion when regenerate fails',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen_fail',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_regen_fail': Todo(
          id: 'todo_regen_fail',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      suggestionsByTodoId: const <String, List<TodoFollowupSuggestion>>{
        'todo_regen_fail': <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 's_old',
            todoId: 'todo_regen_fail',
            content: '旧建议',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'old',
            citationsJson: null,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        ],
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      errorsByMode: <TodoFollowupGenerationMode, Object>{
        TodoFollowupGenerationMode.modelKnowledge: StateError('boom'),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastDismissedSuggestionIds, isEmpty);
    expect(store.pendingSuggestionsFor('todo_regen_fail').single.id, 's_old');
  });

  test('runner schedules retries from the actual failure time', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_retry_clock',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_retry_clock': Todo(
          id: 'todo_retry_clock',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      errorsByMode: <TodoFollowupGenerationMode, Object>{
        TodoFollowupGenerationMode.modelKnowledge: StateError('boom'),
      },
    );
    final clockValues = <int>[1000, 5000, 31000];
    var clockIndex = 0;

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () {
        final index = clockIndex < clockValues.length
            ? clockIndex++
            : clockValues.length - 1;
        return clockValues[index];
      },
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastFailedTodoId, 'todo_retry_clock');
    expect(store.lastFailedNowMs, 31000);
    expect(store.lastFailedNextRetryAtMs, 61000);
  });

  test(
      'runner preserves existing pending suggestion when regenerate is identical',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen_same',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_regen_same': Todo(
          id: 'todo_regen_same',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      suggestionsByTodoId: const <String, List<TodoFollowupSuggestion>>{
        'todo_regen_same': <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 's_old',
            todoId: 'todo_regen_same',
            content: '以下内容基于模型知识整理，未联网核实。',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'old',
            citationsJson: null,
            createdAtMs: 0,
            updatedAtMs: 0,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        ],
      },
    );
    final client = _FakeClient(
      supportsWebSearch: false,
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容基于模型知识整理，未联网核实。',
          mode: TodoFollowupGenerationMode.modelKnowledge,
          citations: <TodoFollowupCitationDraft>[],
        ),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
      ),
      nowMs: () => 1000,
    );

    await runner.runOnce(localeTag: 'zh-CN');

    expect(store.lastDismissedSuggestionIds, isEmpty);
    expect(store.pendingSuggestionsFor('todo_regen_same'), hasLength(1));
    expect(store.pendingSuggestionsFor('todo_regen_same').single.id, 's_old');
    expect(store.lastSucceededTodoId, 'todo_regen_same');
  });
}

final class _FakeStore implements TodoFollowupGenerationStore {
  _FakeStore({
    required List<TodoFollowupGenerationJob> jobs,
    required Map<String, Todo> todos,
    Map<String, List<TodoActivity>>? activitiesByTodoId,
    Map<String, List<TodoFollowupSuggestion>>? suggestionsByTodoId,
  })  : _jobs = List<TodoFollowupGenerationJob>.from(jobs),
        _todos = Map<String, Todo>.from(todos),
        _activitiesByTodoId = <String, List<TodoActivity>>{
          for (final entry
              in (activitiesByTodoId ?? const <String, List<TodoActivity>>{})
                  .entries)
            entry.key: List<TodoActivity>.from(entry.value),
        },
        _suggestionsByTodoId = <String, List<TodoFollowupSuggestion>>{
          for (final entry in (suggestionsByTodoId ??
                  const <String, List<TodoFollowupSuggestion>>{})
              .entries)
            entry.key: List<TodoFollowupSuggestion>.from(entry.value),
        };

  final List<TodoFollowupGenerationJob> _jobs;
  final Map<String, Todo> _todos;
  final Map<String, List<TodoActivity>> _activitiesByTodoId;
  final Map<String, List<TodoFollowupSuggestion>> _suggestionsByTodoId;

  String? lastSucceededTodoId;
  String? lastSkippedTodoId;
  String? lastFailedTodoId;
  int? lastFailedNowMs;
  int? lastFailedNextRetryAtMs;
  List<String> lastDismissedSuggestionIds = <String>[];
  List<TodoFollowupSuggestionDraftInput> lastUpsertedSuggestions =
      <TodoFollowupSuggestionDraftInput>[];

  List<TodoFollowupSuggestion> pendingSuggestionsFor(String todoId) {
    final items =
        _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[];
    return items
        .where((item) => item.state == 'pending')
        .toList(growable: false);
  }

  @override
  Future<Todo?> getTodo(String todoId) async => _todos[todoId];

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) async =>
      List<TodoActivity>.from(
          _activitiesByTodoId[todoId] ?? const <TodoActivity>[]);

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) async =>
      List<TodoFollowupSuggestion>.from(
        _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[],
      );

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async =>
      List<TodoFollowupGenerationJob>.from(_jobs.take(limit));

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    lastDismissedSuggestionIds = List<String>.from(suggestionIds);
    _suggestionsByTodoId[todoId] =
        (_suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[])
            .where((item) => !suggestionIds.contains(item.id))
            .toList(growable: false);
  }

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    lastFailedTodoId = todoId;
    lastFailedNowMs = nowMs;
    lastFailedNextRetryAtMs = nextRetryAtMs;
  }

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) async {
    lastSkippedTodoId = todoId;
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) async {
    lastSucceededTodoId = todoId;
  }

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {
    lastUpsertedSuggestions =
        List<TodoFollowupSuggestionDraftInput>.from(suggestions);
    final next = List<TodoFollowupSuggestion>.from(
      _suggestionsByTodoId[todoId] ?? const <TodoFollowupSuggestion>[],
    );
    final blocked = next
        .where((item) => item.state == 'pending')
        .map((item) => item.content.trim())
        .toSet();
    for (final suggestion in suggestions) {
      final content = suggestion.content.trim();
      if (content.isEmpty || !blocked.add(content)) continue;
      next.add(
        TodoFollowupSuggestion(
          id: 'generated_${next.length + 1}',
          todoId: todoId,
          content: content,
          state: 'pending',
          source: source,
          generationMode: suggestion.generationMode,
          generationKey: generationKey,
          citationsJson: suggestion.citationsJson,
          createdAtMs: 0,
          updatedAtMs: 0,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      );
    }
    _suggestionsByTodoId[todoId] = next;
  }
}

final class _FakeClient implements TodoFollowupGenerationClient {
  _FakeClient({
    required this.supportsWebSearch,
    this.responseByMode =
        const <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{},
    this.errorsByMode = const <TodoFollowupGenerationMode, Object>{},
  });

  @override
  final bool supportsWebSearch;

  @override
  final String source = 'cloud';

  final Map<TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>
      responseByMode;
  final Map<TodoFollowupGenerationMode, Object> errorsByMode;
  final List<TodoFollowupGenerationMode> requestedModes =
      <TodoFollowupGenerationMode>[];
  List<String> lastManualFollowups = <String>[];
  String? lastTaskContext;

  @override
  Future<TodoFollowupSuggestionDraft?> generate({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required TodoFollowupGenerationMode generationMode,
    required List<String> manualFollowups,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  }) async {
    requestedModes.add(generationMode);
    lastManualFollowups = List<String>.from(manualFollowups);
    lastTaskContext = taskContext;
    final error = errorsByMode[generationMode];
    if (error != null) throw error;
    return responseByMode[generationMode];
  }
}
