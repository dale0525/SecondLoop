import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';

import 'semantic_parse_local_first_runner_test_support.dart';

void main() {
  test('runner skips AI for high-confidence local todo command', () async {
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

    await runner.runOnce(localeTag: 'zh-CN', dayEndMinutes: 21 * 60);

    expect(client.parseRequests, 0);
    expect(store.jobState('msg:priority')?.appliedActionKind, 'none');
  });

  test('runner requests AI when todo command target is ambiguous', () async {
    final store = FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:rename',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:rename': '把报销改成提交差旅报销'},
      openCandidates: const [
        SemanticParseTodoCandidate(id: 'todo:1', title: '报销', status: 'open'),
        SemanticParseTodoCandidate(id: 'todo:2', title: '报销', status: 'open'),
      ],
    );
    final client = FakeSemanticParseClient(
      responseJson: '{"kind":"none","confidence":0.0}',
    );
    final runner = _runner(store: store, client: client);

    await runner.runOnce(localeTag: 'zh-CN', dayEndMinutes: 21 * 60);

    expect(client.parseRequests, 1);
    expect(client.lastLocalResultJson, contains('"ambiguous_todo_command"'));
    expect(
        client.lastLocalResultJson, contains('"todo_command_ambiguous":true'));
    expect(client.lastUnresolvedFields, contains('target_todo_id'));
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
