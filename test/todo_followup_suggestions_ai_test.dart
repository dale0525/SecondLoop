import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_followup_suggestions_ai.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('followup prompt asks for information follow-up note', () {
    final prompt = buildTodoFollowupSuggestionPrompt(
      taskTitle: '调研一下当前主流的 llm 模型',
      taskContext: '已有笔记：关注价格、上下文、多模态。',
      localeTag: 'zh-CN',
      generationMode: TodoFollowupGenerationMode.modelKnowledge,
      manualFollowups: const <String>[],
    );

    expect(prompt, contains('information follow-up'));
    expect(prompt, contains('Do not tell the user what to research next'));
    expect(prompt, contains('未联网核实'));
  });

  test('followup parser reads fenced json and citations', () {
    const raw = '''```json
{"content":"## Summary\\nClaude / GPT / Gemini 仍是主流商用选项。","mode":"web_search","citations":[{"title":"OpenAI Models","url":"https://openai.com","domain":"openai.com"},{"title":"OpenAI Models","url":"https://openai.com","domain":"openai.com"}]}
```''';

    final parsed = parseTodoFollowupSuggestionJson(raw);

    expect(parsed, isNotNull);
    expect(parsed!.content, contains('主流商用选项'));
    expect(parsed.mode, TodoFollowupGenerationMode.webSearch);
    expect(parsed.citations.length, 1);
    expect(parsed.citations.single.domain, 'openai.com');
  });

  test('followup parser falls back to model knowledge on invalid mode', () {
    final parsed = parseTodoFollowupSuggestionJson(
      '{"content":"hello","mode":"unknown","citations":[]}',
    );

    expect(parsed, isNotNull);
    expect(parsed!.mode, TodoFollowupGenerationMode.modelKnowledge);
  });

  test('followup context keeps only manual followup notes', () {
    final context = buildTodoFollowupSuggestionContext(
      todo: const Todo(
        id: 'todo_1',
        title: '去浦东机场接 MU5101',
        dueAtMs: null,
        status: 'open',
        sourceEntryId: null,
        createdAtMs: 0,
        updatedAtMs: 0,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: null,
      ),
      activities: const <TodoActivity>[
        TodoActivity(
          id: 'a1',
          todoId: 'todo_1',
          activityType: 'note',
          fromStatus: null,
          toStatus: null,
          content: '已确认是明天下午。',
          sourceMessageId: null,
          createdAtMs: 1,
        ),
        TodoActivity(
          id: 'a2',
          todoId: 'todo_1',
          activityType: 'followup_information',
          fromStatus: null,
          toStatus: null,
          content: '这是旧的 AI follow-up。',
          sourceMessageId: null,
          createdAtMs: 2,
        ),
      ],
      includeManualFollowupsOnly: true,
    );

    expect(context, contains('已确认是明天下午。'));
    expect(context, isNot(contains('旧的 AI follow-up')));
  });
}
