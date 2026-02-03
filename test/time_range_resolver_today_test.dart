import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/time/time_range_resolver.dart';

void main() {
  test('LocalTimeRangeResolver resolves today (zh)', () {
    final nowLocal = DateTime(2026, 2, 3, 15, 30);
    final res = LocalTimeRangeResolver.resolve(
      '今天有哪些事要做？',
      nowLocal,
      locale: const Locale('zh', 'CN'),
      firstDayOfWeekIndex: 0,
    );

    expect(res?.kind, 'today');
    expect(res?.startLocal, DateTime(2026, 2, 3));
    expect(res?.endLocal, DateTime(2026, 2, 4));
  });

  test('LocalTimeRangeResolver resolves today (en)', () {
    final nowLocal = DateTime(2026, 2, 3, 15, 30);
    final res = LocalTimeRangeResolver.resolve(
      'what should I do today?',
      nowLocal,
      locale: const Locale('en', 'US'),
      firstDayOfWeekIndex: 0,
    );

    expect(res?.kind, 'today');
    expect(res?.startLocal, DateTime(2026, 2, 3));
    expect(res?.endLocal, DateTime(2026, 2, 4));
  });
}
