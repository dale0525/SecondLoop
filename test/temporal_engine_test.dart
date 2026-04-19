import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/temporal/temporal_engine.dart';
import 'package:secondloop/core/ai/temporal/temporal_resolution.dart';

void main() {
  final now = DateTime(2026, 2, 4, 10, 0);

  test('retrieval_window projects 上周 into an inclusive past range', () {
    final result = TemporalEngine.resolve(
      text: '上周聊过什么',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.retrievalWindow,
      allowEnhancement: false,
    );

    expect(result.resolver, TemporalResolver.rule);
    expect(result.semantics, TemporalSemantics.rangePast);
    expect(result.startLocal, DateTime(2026, 1, 26));
    expect(result.endLocal, DateTime(2026, 2, 2));
  });

  test('todo_due rejects 上周 and degrades to none', () {
    final result = TemporalEngine.resolve(
      text: '上周提醒我报税',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.todoDue,
      allowEnhancement: false,
    );

    expect(result.resolver, TemporalResolver.none);
    expect(result.semantics, TemporalSemantics.none);
    expect(result.dueAtLocal, isNull);
  });

  test('todo_followup_due resolves 年初一之后第一个工作日 via zh-CN locale plugin', () {
    final result = TemporalEngine.resolve(
      text: '把报销改到年初一之后第一个工作日',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.todoFollowupDue,
      allowEnhancement: false,
    );

    expect(result.resolver, TemporalResolver.localePlugin);
    expect(result.semantics, TemporalSemantics.pointInTime);
    expect(result.dueAtLocal, isNotNull);
    expect(result.metadata.inferredCalendarSystem, 'chinese_lunar');
  });

  test('todo_due keeps übermorgen as day-after-tomorrow instead of morgen', () {
    final result = TemporalEngine.resolve(
      text: 'übermorgen',
      nowLocal: now,
      locale: const Locale('de'),
      timezone: 'Europe/Berlin',
      firstDayOfWeek: 1,
      mode: TemporalMode.todoDue,
      allowEnhancement: false,
      dayEndMinutes: 21 * 60,
    );

    expect(result.dueAtLocal, DateTime(2026, 2, 6, 21, 0));
    expect(result.metadata.normalizedExpression, 'übermorgen');
  });

  test('todo_due supports localized relative-day and weekday expressions', () {
    final cases = <({
      String text,
      Locale locale,
      DateTime expectedDueAt,
      String expectedNormalized,
    })>[
      (
        text: 'après-demain',
        locale: const Locale('fr'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
        expectedNormalized: 'après-demain',
      ),
      (
        text: '明後日',
        locale: const Locale('ja'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
        expectedNormalized: '明後日',
      ),
      (
        text: '모레',
        locale: const Locale('ko'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
        expectedNormalized: '모레',
      ),
      (
        text: 'mardi',
        locale: const Locale('fr'),
        expectedDueAt: DateTime(2026, 2, 10, 21, 0),
        expectedNormalized: 'mardi',
      ),
      (
        text: '금요일',
        locale: const Locale('ko'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
        expectedNormalized: '금요일',
      ),
    ];

    for (final c in cases) {
      final result = TemporalEngine.resolve(
        text: c.text,
        nowLocal: now,
        locale: c.locale,
        timezone: '',
        firstDayOfWeek: 1,
        mode: TemporalMode.todoDue,
        allowEnhancement: false,
        dayEndMinutes: 21 * 60,
      );

      expect(
        result.dueAtLocal,
        c.expectedDueAt,
        reason: 'text=${c.text} locale=${c.locale}',
      );
      expect(
        result.metadata.normalizedExpression,
        c.expectedNormalized,
        reason: 'text=${c.text} locale=${c.locale}',
      );
    }
  });

  test('retrieval_window supports last week in legacy localized phrases', () {
    final cases = <({String text, Locale locale})>[
      (text: 'la semaine dernière', locale: const Locale('fr')),
      (text: 'letzte woche', locale: const Locale('de')),
      (text: '先週', locale: const Locale('ja')),
      (text: '지난주', locale: const Locale('ko')),
    ];

    for (final c in cases) {
      final result = TemporalEngine.resolve(
        text: c.text,
        nowLocal: now,
        locale: c.locale,
        timezone: '',
        firstDayOfWeek: 1,
        mode: TemporalMode.retrievalWindow,
        allowEnhancement: false,
      );

      expect(result.semantics, TemporalSemantics.rangePast,
          reason: 'text=${c.text} locale=${c.locale}');
      expect(result.startLocal, DateTime(2026, 1, 26),
          reason: 'text=${c.text} locale=${c.locale}');
      expect(result.endLocal, DateTime(2026, 2, 2),
          reason: 'text=${c.text} locale=${c.locale}');
    }
  });

  test('retrieval_window treats this week as a range spanning past and future',
      () {
    final cases = <({String text, Locale locale})>[
      (text: 'this week', locale: const Locale('en')),
      (text: '本周', locale: const Locale('zh', 'CN')),
    ];

    for (final c in cases) {
      final result = TemporalEngine.resolve(
        text: c.text,
        nowLocal: now,
        locale: c.locale,
        timezone: '',
        firstDayOfWeek: 1,
        mode: TemporalMode.retrievalWindow,
        allowEnhancement: false,
      );

      expect(result.semantics, TemporalSemantics.rangeBoth,
          reason: 'text=${c.text} locale=${c.locale}');
      expect(result.startLocal, DateTime(2026, 2, 2),
          reason: 'text=${c.text} locale=${c.locale}');
      expect(result.endLocal, DateTime(2026, 2, 9),
          reason: 'text=${c.text} locale=${c.locale}');
    }
  });

  test('retrieval_window treats yesterday as a past-only range', () {
    final result = TemporalEngine.resolve(
      text: 'yesterday',
      nowLocal: now,
      locale: const Locale('en'),
      timezone: '',
      firstDayOfWeek: 1,
      mode: TemporalMode.retrievalWindow,
      allowEnhancement: false,
    );

    expect(result.semantics, TemporalSemantics.rangePast);
    expect(result.startLocal, DateTime(2026, 2, 3));
    expect(result.endLocal, DateTime(2026, 2, 4));
  });

  test('todo_due keeps same-day weekday on today when no explicit time', () {
    final result = TemporalEngine.resolve(
      text: '周三',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: '',
      firstDayOfWeek: 1,
      mode: TemporalMode.todoDue,
      allowEnhancement: false,
      dayEndMinutes: 21 * 60,
    );

    expect(result.dueAtLocal, DateTime(2026, 2, 4, 21, 0));
    expect(result.metadata.normalizedExpression, '周三');
  });

  test('todo_followup_due keeps zh-CN holiday expressions working after 2026',
      () {
    final result = TemporalEngine.resolve(
      text: '把报销改到节后第一个工作日',
      nowLocal: DateTime(2027, 2, 1, 10, 0),
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.todoFollowupDue,
      allowEnhancement: false,
      dayEndMinutes: 21 * 60,
    );

    expect(result.resolver, TemporalResolver.localePlugin);
    expect(result.dueAtLocal, DateTime(2027, 2, 15, 21, 0));
    expect(result.metadata.inferredCalendarSystem, 'chinese_lunar');
  });

  test('retrieval_window treats 春节后 as a past-open window after the holiday',
      () {
    final now = DateTime(2026, 3, 1, 10, 0);
    final result = TemporalEngine.resolve(
      text: '春节后聊过什么',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.retrievalWindow,
      allowEnhancement: false,
    );

    expect(result.resolver, TemporalResolver.localePlugin);
    expect(result.semantics, TemporalSemantics.rangePast);
    expect(result.startLocal, DateTime(2026, 2, 24));
    expect(result.endLocal, now);
  });

  test(
      'retrieval_window uses the most recent Spring Festival boundary instead of next year',
      () {
    final now = DateTime(2027, 3, 1, 10, 0);
    final result = TemporalEngine.resolve(
      text: '春节后都处理了哪些报销',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      timezone: 'Asia/Shanghai',
      firstDayOfWeek: 1,
      mode: TemporalMode.retrievalWindow,
      allowEnhancement: false,
    );

    expect(result.resolver, TemporalResolver.localePlugin);
    expect(result.semantics, TemporalSemantics.rangePast);
    expect(result.startLocal, DateTime(2027, 2, 15));
    expect(result.endLocal, now);
  });
}
