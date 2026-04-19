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

    expect(result.kind, AskAiIntentKind.both);
    expect(result.timeRange?.startLocal, DateTime(2026, 2, 2));
    expect(result.timeRange?.endLocal, DateTime(2026, 2, 9));
  });

  test('Ask AI does not treat 答应 alone as future intent', () {
    final result = AskAiIntentResolver.resolve(
      '我答应过什么',
      DateTime(2026, 2, 4, 10, 0),
      locale: const Locale('zh', 'CN'),
      firstDayOfWeekIndex: 1,
    );

    expect(result.kind, AskAiIntentKind.none);
    expect(result.timeRange, isNull);
  });

  test('Ask AI maps this week history question to both', () {
    final result = AskAiIntentResolver.resolve(
      'what did I do this week',
      DateTime(2026, 2, 4, 10, 0),
      locale: const Locale('en'),
      firstDayOfWeekIndex: 1,
    );

    expect(result.kind, AskAiIntentKind.both);
    expect(result.timeRange?.startLocal, DateTime(2026, 2, 2));
    expect(result.timeRange?.endLocal, DateTime(2026, 2, 9));
  });
}
