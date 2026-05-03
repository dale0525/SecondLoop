import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/local_semantic_parse_result.dart';
import 'package:secondloop/core/ai/local_semantic_parser.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/features/actions/todo/todo_linking.dart';

void main() {
  test('local parser exposes high-confidence todo command without enhancement',
      () {
    final result = LocalSemanticParser.parse(
      text: '把报销优先级调高',
      nowLocal: DateTime(2026, 5, 4, 9),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const [
        TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
      ],
    );

    expect(result.kind, LocalSemanticParseKind.none);
    expect(result.todoCommand?.kind, SecretaryTodoCommandKind.reprioritize);
    expect(result.todoCommand?.confidence, greaterThanOrEqualTo(0.9));
    expect(result.diagnostics.todoCommandIntent, 'reprioritize');
    expect(result.diagnostics.todoCommandNeedsEnhancement, isFalse);
  });

  test('local parser treats clear delete as confirmable todo command', () {
    final result = LocalSemanticParser.parse(
      text: '删除报销',
      nowLocal: DateTime(2026, 5, 4, 9),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const [
        TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
      ],
    );

    expect(result.kind, LocalSemanticParseKind.none);
    expect(result.todoCommand?.kind, SecretaryTodoCommandKind.dismiss);
    expect(result.diagnostics.todoCommandIntent, 'dismiss');
  });

  test('ambiguous todo command returns none with enhancement diagnostic', () {
    final result = LocalSemanticParser.parse(
      text: '把报销改成提交差旅报销',
      nowLocal: DateTime(2026, 5, 4, 9),
      locale: const Locale('zh', 'CN'),
      openTodoTargets: const [
        TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
        TodoLinkTarget(id: 'todo-2', title: '报销', status: 'open'),
      ],
    );

    expect(result.kind, LocalSemanticParseKind.none);
    expect(result.todoCommand, isNull);
    expect(result.diagnostics.localIntent, 'ambiguous_todo_command');
    expect(result.diagnostics.todoCommandAmbiguous, isTrue);
    expect(result.diagnostics.todoCommandNeedsEnhancement, isTrue);
  });
}
