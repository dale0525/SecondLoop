import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_checklist_suggestions_ai.dart';

void main() {
  test('checklist prompt uses parser max-item constant', () {
    final prompt = buildTodoChecklistSuggestionsPrompt(
      taskTitle: 'Plan launch',
      taskContext: 'Need a practical rollout checklist.',
      localeTag: 'en-US',
    );

    expect(
      prompt,
      contains('Suggest 0 to $kMaxGeneratedChecklistSuggestions checklist items.'),
    );
  });

  test('checklist parser caps output at max generated suggestions', () {
    final rawSuggestions = List<String>.generate(
      kMaxGeneratedChecklistSuggestions + 4,
      (index) => 'Step ${index + 1}',
    );

    final parsed = parseTodoChecklistSuggestionsJson(
      '{"suggestions": ${rawSuggestions.map((item) => '"$item"').toList()}}',
    );

    expect(parsed.length, kMaxGeneratedChecklistSuggestions);
    expect(parsed.first, 'Step 1');
    expect(parsed.last, 'Step $kMaxGeneratedChecklistSuggestions');
  });
}
