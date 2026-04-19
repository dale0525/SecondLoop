import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/temporal/temporal_engine.dart';
import 'package:secondloop/core/ai/temporal/temporal_resolution.dart';

void main() {
  test('retrieval_window projects 上周 into an inclusive past range', () {
    final result = TemporalEngine.resolve(
      text: '上周聊过什么',
      nowLocal: DateTime(2026, 2, 4, 10, 0),
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
      nowLocal: DateTime(2026, 2, 4, 10, 0),
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
      nowLocal: DateTime(2026, 2, 4, 10, 0),
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
}
