import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/time/time_resolver.dart';

void main() {
  test('resolves weekend (zh) into Sat/Sun candidates', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '周末做某事',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'weekend');
    expect(res.candidates.length, 2);
    expect(res.candidates[0].dueAtLocal, DateTime(2026, 1, 24, 21, 0));
    expect(res.candidates[1].dueAtLocal, DateTime(2026, 1, 25, 21, 0));
  });

  test('resolves month start (zh) to next occurrence', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '月初记得交房租',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'month_start');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 2, 1, 21, 0));
  });

  test('resolves month end (zh) in same month', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '月底报税',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'month_end');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 1, 31, 21, 0));
  });

  test('resolves fixed holiday (zh) as next occurrence', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '圣诞节买礼物',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'holiday');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 12, 25, 21, 0));
  });

  test('resolves tomorrow (zh) to next day at day end', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '明天分析数据',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'relative_day');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 1, 25, 21, 0));
  });

  test('resolves tomorrow (en) to next day at day end', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      'analyze data tomorrow',
      now,
      locale: const Locale('en'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'relative_day');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 1, 25, 21, 0));
  });

  test('resolves weekday (zh) to next occurrence', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '周一做狗狗的口粮',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'weekday');
    expect(res.candidates.single.dueAtLocal, DateTime(2026, 1, 26, 21, 0));
  });

  test('resolves time-only (zh) into today/tomorrow candidates', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '下午3点做某事',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.kind, 'time_only');
    expect(res.candidates.length, 2);
    expect(res.candidates[0].dueAtLocal, DateTime(2026, 1, 24, 15, 0));
    expect(res.candidates[1].dueAtLocal, DateTime(2026, 1, 25, 15, 0));
  });

  test('resolves relative day + time (zh) to exact time', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final res = LocalTimeResolver.resolve(
      '明天下午3点分析数据',
      now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(res, isNotNull);
    expect(res!.candidates.single.dueAtLocal, DateTime(2026, 1, 25, 15, 0));
  });

  test('detects review intent keywords', () {
    expect(LocalTimeResolver.looksLikeReviewIntent('记得要做某事'), isTrue);
    expect(LocalTimeResolver.looksLikeReviewIntent('Remember to do X'), isTrue);
    expect(LocalTimeResolver.looksLikeReviewIntent('Just a note'), isFalse);
  });
}
