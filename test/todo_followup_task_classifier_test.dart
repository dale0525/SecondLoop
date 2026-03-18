import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_followup_task_classifier.dart';

void main() {
  test('classifies research-like tasks using fixed enums', () {
    expect(
      classifyTodoFollowupTaskType('调研一下当前主流的 llm 模型'),
      TodoFollowupTaskType.research,
    );
    expect(
      classifyTodoFollowupTaskType('比较 Cursor、Windsurf 和 Copilot 的能力'),
      TodoFollowupTaskType.comparison,
    );
  });

  test('classifies live info lookup tasks using fixed enums', () {
    expect(
      classifyTodoFollowupTaskType('去浦东机场接 MU5101'),
      TodoFollowupTaskType.liveInfoLookup,
    );
    expect(
      classifyTodoFollowupTaskType('去浦东机场接 mu5101'),
      TodoFollowupTaskType.liveInfoLookup,
    );
    expect(
      classifyTodoFollowupTaskType('查一下上海迪士尼停车和入园时间'),
      TodoFollowupTaskType.liveInfoLookup,
    );
  });

  test('classifies execution and unknown without freeform labels', () {
    expect(
      classifyTodoFollowupTaskType('修复登录页闪退'),
      TodoFollowupTaskType.execution,
    );
    expect(
      classifyTodoFollowupTaskType('周五之前处理一下'),
      TodoFollowupTaskType.unknown,
    );
    expect(
      classifyTodoFollowupTaskType('AB 1234 这个编号记一下'),
      TodoFollowupTaskType.unknown,
    );

    for (final value in TodoFollowupTaskType.values) {
      expect(value.wireValue, isNotEmpty);
      expect(
        const <String>{
          'execution',
          'research',
          'comparison',
          'live_info_lookup',
          'reference_collection',
          'coordination',
          'planning',
          'unknown',
        },
        contains(value.wireValue),
      );
    }
  });

  test('auto follow-up allows only information-gathering task types', () {
    expect(TodoFollowupTaskType.research.allowsAutoFollowup, isTrue);
    expect(TodoFollowupTaskType.comparison.allowsAutoFollowup, isTrue);
    expect(TodoFollowupTaskType.liveInfoLookup.allowsAutoFollowup, isTrue);
    expect(TodoFollowupTaskType.referenceCollection.allowsAutoFollowup, isTrue);
    expect(TodoFollowupTaskType.execution.allowsAutoFollowup, isFalse);
    expect(TodoFollowupTaskType.planning.allowsAutoFollowup, isFalse);
    expect(TodoFollowupTaskType.unknown.allowsAutoFollowup, isFalse);
  });
}
