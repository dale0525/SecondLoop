import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';

import 'semantic_parse_local_first_runner_test_support.dart';

void main() {
  test('runner treats same-due followup as no action', () async {
    final existingDueAtLocal = DateTime(2026, 2, 5, 21, 0);
    final store = FakeSemanticParseStore(
      jobs: const <SemanticParseAutoActionJob>[
        SemanticParseAutoActionJob(
          messageId: 'msg:noop_followup_due',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          createdAtMs: 0,
        ),
      ],
      messages: const <String, String>{'msg:noop_followup_due': '把报销改到明天'},
      openCandidates: <SemanticParseTodoCandidate>[
        SemanticParseTodoCandidate(
          id: 'todo:1',
          title: '报销',
          status: 'open',
          dueLocalIso: existingDueAtLocal.toIso8601String(),
        ),
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

    expect(result.processed, 0);
    expect(result.didMutateAny, isFalse);
    expect(store.updatedStatusByTodoId, isEmpty);
    expect(store.updatedDueByTodoId, isEmpty);
    expect(store.jobState('msg:noop_followup_due')?.appliedActionKind, 'none');
    expect(client.parseRequests, 0);
  });
}
