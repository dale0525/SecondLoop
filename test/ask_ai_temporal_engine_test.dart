import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/ask_ai_intent_resolver.dart';

void main() {
  test('Ask AI uses temporal engine for 本周 retrieval scope', () {
    final result = AskAiIntentResolver.resolve(
      '本周我答应了谁什么事？',
      DateTime(2026, 2, 4, 10, 0),
      locale: const Locale('zh', 'CN'),
      firstDayOfWeekIndex: 1,
    );

    expect(result.kind, AskAiIntentKind.future);
    expect(result.timeRange?.startLocal, DateTime(2026, 2, 2));
    expect(result.timeRange?.endLocal, DateTime(2026, 2, 9));
  });
}
