import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_answer_evidence_parser.dart';

void main() {
  test('parseChatAnswerEvidence ignores legacy memory cards', () {
    const raw = '''
{
  "direct_sources": [
    {
      "id": "message:history-1",
      "href": "secondloop://message/history-1",
      "source_type": "message",
      "label": "History",
      "source_type_label": "chat_message",
      "scope_label": "this_thread",
      "confidence_label": "high_relevance",
      "title": "Kickoff notes",
      "snippet": "Kickoff moved to Friday afternoon.",
      "highlighted_text": "Kickoff moved to Friday afternoon.",
      "created_at_ms": 1,
      "updated_at_ms": 2
    }
  ],
  "memory_cards": [
    {
      "document_id": "generated:preference:response-language",
      "title": "Response language",
      "summary": "User prefers Chinese.",
      "source_kind": "summary",
      "role": "summary",
      "created_at_ms": 3,
      "updated_at_ms": 4,
      "status": "confirmed",
      "source_count": 2,
      "why_used": "用中文总结一下最近变化"
    }
  ]
}
''';

    final evidence = parseChatAnswerEvidence(raw);

    expect(evidence, isNotNull);
    expect(evidence!.directSources, hasLength(1));
    expect(evidence.memoryCards, isEmpty);
    expect(
      evidence.directSources.single.displayTitle,
      'Kickoff notes',
    );
    expect(evidence.directSources.single.sourceTypeLabel, 'chat_message');
    expect(evidence.directSources.single.scopeLabel, 'this_thread');
    expect(evidence.directSources.single.confidenceLabel, 'high_relevance');
    expect(
      evidence.directSources.single.displaySnippet,
      'Kickoff moved to Friday afternoon.',
    );
    expect(
      evidence.chipLabelForHref('secondloop://message/history-1'),
      '[1]',
    );
  });

  test('parseChatAnswerEvidence returns null for invalid payload', () {
    expect(parseChatAnswerEvidence('not-json'), isNull);
    expect(parseChatAnswerEvidence('{"direct_sources":[],"memory_cards":[]}'),
        isNull);
  });

  test('parseChatAnswerEvidence aggregates duplicate href citations', () {
    const raw = '''
{
  "direct_sources": [
    {
      "id": "attachment:sha:chunk:1",
      "href": "secondloop://attachment/sha",
      "source_type": "attachment",
      "label": "Attachment",
      "snippet": "First excerpt",
      "unit_id": "unit-a"
    },
    {
      "id": "attachment:sha:chunk:2",
      "href": "secondloop://attachment/sha",
      "source_type": "attachment",
      "label": "Attachment",
      "snippet": "Second excerpt",
      "unit_id": "unit-b"
    }
  ],
  "memory_cards": []
}
''';

    final evidence = parseChatAnswerEvidence(raw);

    expect(evidence, isNotNull);
    expect(
      evidence!.chipLabelForHref('secondloop://attachment/sha'),
      '[1, 2]',
    );
  });
}
