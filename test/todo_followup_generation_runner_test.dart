import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/ai/todo_followup_suggestions_ai.dart';
import 'package:secondloop/src/rust/db.dart';

part 'todo_followup_generation_runner_test_fakes.dart';

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
      TodoFollowupGenerationMode.webSearch,
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
    final client = _FakeClient();

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
    expect(client.lastTaskContext, isNot(contains('用户补充：优先关注价格和 API 稳定性')));
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

  test('runner manual regenerate prefers persisted task type hint', () async {
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
    expect(store.lastSkippedTodoId, 'todo_regen_reclassify');
    expect(store.lastSucceededTodoId, isNull);
    expect(client.requestedModes, isEmpty);
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

  test('runner keeps manual regenerate queued for retry after errors',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_retry',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_manual_retry': Todo(
          id: 'todo_manual_retry',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
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

    expect(store.lastFailedTodoId, 'todo_manual_retry');
    expect(store.lastCanceledTodoId, isNull);
    expect(store.lastFailedNextRetryAtMs, 121000);
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

  test(
      'runner preserves normalized-equivalent pending suggestions after regenerate',
      () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_regen_normalized',
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
        'todo_regen_normalized': Todo(
          id: 'todo_regen_normalized',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
      suggestionsByTodoId: const <String, List<TodoFollowupSuggestion>>{
        'todo_regen_normalized': <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 's_old',
            todoId: 'todo_regen_normalized',
            content: '以下内容 基于模型知识整理，未联网核实。',
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
      responseByMode: <TodoFollowupGenerationMode, TodoFollowupSuggestionDraft>{
        TodoFollowupGenerationMode.modelKnowledge:
            const TodoFollowupSuggestionDraft(
          content: '以下内容  基于模型知识整理，未联网核实。',
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
    expect(store.pendingSuggestionsFor('todo_regen_normalized'), hasLength(1));
    expect(store.pendingSuggestionsFor('todo_regen_normalized').single.id,
        's_old');
    expect(
      store.pendingSuggestionsFor('todo_regen_normalized').single.generationKey,
      'followup:manual_regenerate:research:1000',
    );
    expect(store.lastSucceededTodoId, 'todo_regen_normalized');
  });

  test('runner cancels manual regenerate after max manual attempts', () async {
    final store = _FakeStore(
      jobs: const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_retry_cap',
          triggerKind: 'manual_regenerate',
          status: 'failed',
          attempts: 4,
          nextRetryAtMs: null,
          lastError: 'previous failure',
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      todos: const <String, Todo>{
        'todo_manual_retry_cap': Todo(
          id: 'todo_manual_retry_cap',
          title: '调研一下当前主流的 llm 模型',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      },
    );
    final client = _FakeClient(
      errorsByMode: <TodoFollowupGenerationMode, Object>{
        TodoFollowupGenerationMode.modelKnowledge:
            StateError('permanent followup failure'),
      },
    );

    final runner = TodoFollowupGenerationRunner(
      store: store,
      client: client,
      settings: const TodoFollowupGenerationRunnerSettings(
        hardTimeout: Duration(milliseconds: 200),
        maxManualAttempts: 5,
      ),
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(localeTag: 'zh-CN');

    expect(result.processed, 1);
    expect(store.lastCanceledTodoId, 'todo_manual_retry_cap');
    expect(store.lastFailedTodoId, isNull);
  });
}
