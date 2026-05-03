import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';

import 'semantic_parse_local_first_runner_test_support.dart';

void main() {
  test('runner executes high-confidence local reprioritize command', () async {
    final store = FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:priority',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:priority': '把报销优先级调高'},
      openCandidates: const [
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );
    final client = FakeSemanticParseClient();
    final runner = _runner(store: store, client: client);

    final result = await runner.runOnce(
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
    );

    expect(result.processed, 1);
    expect(client.parseRequests, 0);
    expect(
      store.jobState('msg:priority')?.appliedActionKind,
      'todo_command:reprioritize',
    );
    expect(store.updatedImportanceByTodoId['todo:1'], 1);
    expect(store.updatedUrgencyByTodoId['todo:1'], 1);
  });

  test('runner does not auto-apply dismiss command', () async {
    final store = FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:dismiss',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:dismiss': '删除报销'},
      openCandidates: const [
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );
    final client = FakeSemanticParseClient();
    final runner = _runner(store: store, client: client);

    await runner.runOnce(localeTag: 'zh-CN', dayEndMinutes: 21 * 60);

    expect(client.parseRequests, 0);
    expect(store.jobState('msg:dismiss')?.appliedActionKind, 'none');
    expect(store.updatedStatusByTodoId, isNot(contains('todo:1')));
  });
}

SemanticParseAutoActionsRunner _runner({
  required FakeSemanticParseStore store,
  required FakeSemanticParseClient client,
}) {
  return SemanticParseAutoActionsRunner(
    store: store,
    client: client,
    settings: const SemanticParseAutoActionsRunnerSettings(
      hardTimeout: Duration(milliseconds: 200),
      minAutoConfidence: 0.86,
    ),
    nowMs: () => 1000,
    nowLocal: () => DateTime(2026, 5, 4, 9),
  );
}
