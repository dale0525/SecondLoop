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

  test('strips display-only citation UUID markers from assistant text', () {
    const text = '你之前提到要分析视频开头台词 [08dc5d82-01d1-414d-821f-105df5a2c62e]，'
        '这和今天计划制作短视频 [eca28b30-5614-41a5-9758-662859e9cdfc] 有关。';

    final parsed = parseAssistantMessageActions(text);

    expect(parsed.displayText, '你之前提到要分析视频开头台词，这和今天计划制作短视频有关。');
  });
}
