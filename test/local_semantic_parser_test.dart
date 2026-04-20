import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/local_semantic_parser.dart';
import 'package:secondloop/core/ai/local_semantic_parse_result.dart';
import 'package:secondloop/features/actions/todo/todo_linking.dart';

void main() {
  test('local parser creates obvious todo without LLM', () {
    final result = LocalSemanticParser.parse(
      text: '明天下午 3 点提交材料',
      nowLocal: DateTime(2026, 2, 4, 10, 0),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(result.kind, LocalSemanticParseKind.create);
    expect(result.resolver, SemanticResolver.local);
    expect(result.dueAtLocal, DateTime(2026, 2, 5, 15, 0));
  });

  test('local parser returns none when followup target is ambiguous', () {
    final result = LocalSemanticParser.parse(
      text: '把这个改到下周',
      nowLocal: DateTime(2026, 2, 4, 10, 0),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
        TodoLinkTarget(id: 'todo:2', title: '报销', status: 'open'),
      ],
    );

    expect(result.kind, LocalSemanticParseKind.none);
    expect(result.confidence, lessThan(0.86));
    expect(result.diagnostics.localIntent, 'ambiguous_followup');
  });

  test(
      'local parser keeps followup ambiguity even when temporal parsing needs enhancement',
      () {
    final result = LocalSemanticParser.parse(
      text: '把这个改到节后第一个工作日',
      nowLocal: DateTime(2031, 1, 20, 10, 0),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
        TodoLinkTarget(id: 'todo:2', title: '回访', status: 'open'),
      ],
    );

    expect(result.kind, LocalSemanticParseKind.none);
    expect(result.confidence, lessThan(0.86));
    expect(result.diagnostics.localIntent, 'ambiguous_followup');
    expect(result.diagnostics.temporalNeedsEnhancement, isTrue);
  });
}
