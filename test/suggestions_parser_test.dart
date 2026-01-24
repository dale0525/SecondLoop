import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/suggestions_parser.dart';

void main() {
  test('returns null when no actions fence present', () {
    expect(SuggestionsParser.tryParse('hello world'), isNull);
  });

  test('parses suggestions from fenced JSON block', () {
    const text = '''
Answer...

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"Pay rent","when":"end of month"}]}
```

More text.
''';

    final parsed = SuggestionsParser.tryParse(text);
    expect(parsed, isNotNull);
    expect(parsed!.version, 1);
    expect(parsed.suggestions.length, 1);
    expect(parsed.suggestions.single.type, 'todo');
    expect(parsed.suggestions.single.title, 'Pay rent');
    expect(parsed.suggestions.single.whenText, 'end of month');
  });

  test('stripActionsBlock removes fenced JSON block', () {
    const text = '''
Answer...

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"Pay rent","when":"end of month"}]}
```

More text.
''';

    final stripped = SuggestionsParser.stripActionsBlock(text);
    expect(stripped, contains('Answer...'));
    expect(stripped, contains('More text.'));
    expect(stripped, isNot(contains('secondloop_actions')));
    expect(stripped, isNot(contains('"suggestions"')));
  });

  test('stripActionsBlock hides incomplete fenced JSON block', () {
    const text = '''
Answer...

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"Pay rent"}]}
''';

    final stripped = SuggestionsParser.stripActionsBlock(text);
    expect(stripped, contains('Answer...'));
    expect(stripped, isNot(contains('secondloop_actions')));
    expect(stripped, isNot(contains('"suggestions"')));
  });
}
