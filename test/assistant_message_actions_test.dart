import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/assistant_message_actions.dart';

void main() {
  test('keeps text when no actions block', () {
    const text = 'hello';
    final parsed = parseAssistantMessageActions(text);
    expect(parsed.displayText, text);
    expect(parsed.suggestions, isNull);
  });

  test('strips actions block and returns suggestions', () {
    const text = '''
Answer...

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"Pay rent","when":"end of month"}]}
```
''';

    final parsed = parseAssistantMessageActions(text);
    expect(parsed.displayText, contains('Answer...'));
    expect(parsed.displayText, isNot(contains('secondloop_actions')));
    expect(parsed.suggestions, isNotNull);
    expect(parsed.suggestions!.suggestions.single.title, 'Pay rent');
  });
}
