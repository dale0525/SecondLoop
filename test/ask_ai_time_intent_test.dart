import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/ask_ai_intent_resolver.dart';

void main() {
  test('zh: "上周做了什么" -> past + lastWeek range', () {
    final now = DateTime(2026, 2, 4, 12, 0); // Wed
    final intent = AskAiIntentResolver.resolve(
      '我上周做了什么',
      now,
      locale: const Locale('zh', 'CN'),
      firstDayOfWeekIndex: 1, // Monday
    );

    expect(intent.kind, AskAiIntentKind.past);
    expect(intent.timeRange, isNotNull);
    expect(intent.timeRange!.startLocal, DateTime(2026, 1, 26));
    expect(intent.timeRange!.endLocal, DateTime(2026, 2, 2));
  });

  test('en: "what should I do tomorrow" -> future + tomorrow range', () {
    final now = DateTime(2026, 2, 4, 12, 0); // Wed
    final intent = AskAiIntentResolver.resolve(
      'what should I do tomorrow',
      now,
      locale: const Locale('en'),
      firstDayOfWeekIndex: 1, // Monday
    );

    expect(intent.kind, AskAiIntentKind.future);
    expect(intent.timeRange, isNotNull);
    expect(intent.timeRange!.startLocal, DateTime(2026, 2, 5));
    expect(intent.timeRange!.endLocal, DateTime(2026, 2, 6));
  });

  test('smoke: parses a time range for ja/ko/es/fr/de', () {
    final now = DateTime(2026, 2, 4, 12, 0); // Wed
    final cases = <({Locale locale, String text})>[
      (locale: const Locale('ja'), text: '昨日やったことは？'),
      (locale: const Locale('ko'), text: '내일 뭐 해야 해?'),
      (locale: const Locale('es'), text: 'qué hice ayer'),
      (locale: const Locale('fr'), text: "qu'est-ce que je dois faire demain"),
      (locale: const Locale('de'), text: 'was soll ich morgen tun'),
    ];

    for (final c in cases) {
      final intent = AskAiIntentResolver.resolve(
        c.text,
        now,
        locale: c.locale,
        firstDayOfWeekIndex: 1, // Monday
      );
      expect(
        intent.timeRange,
        isNotNull,
        reason: 'locale=${c.locale} text=${c.text}',
      );
    }
  });
}
