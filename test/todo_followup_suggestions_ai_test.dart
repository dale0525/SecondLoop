import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_followup_suggestions_ai.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
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
    expect(prompt, contains("user's current app language (zh-CN)"));
    expect(prompt, contains('未联网核实'));
  });

  test('model knowledge parser requires localized not-verified disclaimer', () {
    expect(
      parseTodoFollowupSuggestionJson(
        '{"content":"Summary only.","mode":"model_knowledge","citations":[]}',
        localeTag: 'en-US',
      ),
      isNull,
    );

    final parsed = parseTodoFollowupSuggestionJson(
      '{"content":"Not verified online. Summary only.","mode":"model_knowledge","citations":[]}',
      localeTag: 'en-US',
    );

    expect(parsed, isNotNull);
    expect(parsed!.mode, TodoFollowupGenerationMode.modelKnowledge);
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

  test('followup parser drops invalid citation urls and derives domain', () {
    final parsed = parseTodoFollowupSuggestionJson(
      '{"content":"hello","mode":"web_search","citations":[{"title":"Bad","url":"javascript:alert(1)","domain":"evil.example"},{"title":"Good","url":"https://docs.example.com/path","domain":"wrong.example"}]}',
    );

    expect(parsed, isNotNull);
    expect(parsed!.citations, hasLength(1));
    expect(parsed.citations.single.title, 'Good');
    expect(parsed.citations.single.url, 'https://docs.example.com/path');
    expect(parsed.citations.single.domain, 'docs.example.com');
  });

  test('followup parser rejects web search results without valid citations',
      () {
    expect(
      parseTodoFollowupSuggestionJson(
        '{"content":"hello","mode":"web_search","citations":[]}',
      ),
      isNull,
    );

    expect(
      parseTodoFollowupSuggestionJson(
        '{"content":"hello","mode":"web_search","citations":[{"title":"Bad","url":"javascript:alert(1)","domain":"evil.example"}]}',
      ),
      isNull,
    );
  });

  test('followup parser falls back to model knowledge on invalid mode', () {
    final parsed = parseTodoFollowupSuggestionJson(
      '{"content":"Not verified online. hello","mode":"unknown","citations":[]}',
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

  test('citation url parser only allows http and https', () {
    expect(
      tryParseTodoFollowupCitationUrl('https://openai.com/models')?.toString(),
      'https://openai.com/models',
    );
    expect(
      tryParseTodoFollowupCitationUrl('http://example.com/path')?.toString(),
      'http://example.com/path',
    );
    expect(
      tryParseTodoFollowupCitationUrl('javascript:alert(1)'),
      isNull,
    );
    expect(
      tryParseTodoFollowupCitationUrl('file:///tmp/secret'),
      isNull,
    );
  });

  test('cloud followup requests require a non-empty id token', () async {
    await expectLater(
      () => requestTodoFollowupSuggestion(
        backend: _UnusedBackend(),
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        route: AskAiRouteKind.cloudGateway,
        gatewayBaseUrl: 'https://example.com',
        idToken: '  ',
        modelName: 'cloud',
        taskTitle: '调研一下当前主流的 llm 模型',
        taskContext: '已有笔记：关注价格、上下文、多模态。',
        localeTag: 'zh-CN',
        generationMode: TodoFollowupGenerationMode.webSearch,
        manualFollowups: const <String>[],
      ),
      throwsA(isA<StateError>()),
    );
  });
}

final class _UnusedBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
