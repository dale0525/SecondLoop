import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_checklist_suggestions_ai.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  test('checklist prompt uses parser max-item constant', () {
    final prompt = buildTodoChecklistSuggestionsPrompt(
      taskTitle: 'Plan launch',
      taskContext: 'Need a practical rollout checklist.',
      localeTag: 'en-US',
    );

    expect(
      prompt,
      contains(
          'Suggest 0 to $kMaxGeneratedChecklistSuggestions checklist items.'),
    );
    expect(prompt, contains('Task due local ISO: (none)'));
  });

  test('checklist context omits status because prompt has dedicated field', () {
    final contextText = buildTodoChecklistSuggestionContext(
      todo: const Todo(
        id: 't1',
        title: 'Plan launch',
        dueAtMs: null,
        status: 'open',
        sourceEntryId: null,
        createdAtMs: 0,
        updatedAtMs: 0,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: null,
      ),
      activities: const <TodoActivity>[],
    );

    expect(contextText, 'Plan launch');
    expect(contextText, isNot(contains('status: open')));
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

  test('checklist parser falls back to plain text bullet lists', () {
    final parsed = parseTodoChecklistSuggestionsJson('''
- Check current menu and pricing
- Confirm delivery window
- Compare package options
''');

    expect(parsed, const <String>[
      'Check current menu and pricing',
      'Confirm delivery window',
      'Compare package options',
    ]);
  });

  test('checklist parser salvages malformed json suggestion arrays', () {
    final parsed = parseTodoChecklistSuggestionsJson(
      '{"suggestions":["Check current menu and pricing","Confirm delivery window",]}',
    );

    expect(parsed, const <String>[
      'Check current menu and pricing',
      'Confirm delivery window',
    ]);
  });

  test('checklist parser ignores object keys when salvaging malformed json',
      () {
    final parsed = parseTodoChecklistSuggestionsJson(
      '{"items":["Book flight","Pack charger",],"source":"web"}',
    );

    expect(parsed, const <String>[
      'Book flight',
      'Pack charger',
    ]);
  });

  test(
      'checklist parser salvages malformed object arrays via suggestion fields only',
      () {
    final parsed = parseTodoChecklistSuggestionsJson(
      '{"suggestions":[{"text":"Book flight"},{"label":"Pack charger"},]}',
    );

    expect(parsed, const <String>[
      'Book flight',
      'Pack charger',
    ]);
  });

  test('checklist parser salvages malformed nested arrays from loose json', () {
    final parsed = parseTodoChecklistSuggestionsJson(
      '{"suggestions":[{"text":"Book flight","subtasks":["passport"]},{"label":"Pack charger"},],"source":"web"}',
    );

    expect(parsed, const <String>[
      'Book flight',
      'Pack charger',
    ]);
  });

  test(
      'checklist parser ignores prose-only fallbacks after json recovery fails',
      () {
    final parsed = parseTodoChecklistSuggestionsJson('''
Here are a few ideas:
Check current menu and pricing
Confirm delivery window
Compare package options
''');

    expect(parsed, isEmpty);
  });
}
