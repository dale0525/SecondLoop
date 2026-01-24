import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/review/review_backoff.dart';
import 'package:secondloop/features/actions/settings/actions_settings_store.dart';

void main() {
  const settings = ActionsSettings(
    morningTime: TimeOfDay(hour: 8, minute: 0),
    dayEndTime: TimeOfDay(hour: 21, minute: 0),
    weeklyReviewTime: TimeOfDay(hour: 21, minute: 0),
  );

  test('stage0 missed -> stage1 + 3 days later at morning time', () {
    final scheduled = DateTime(2026, 1, 25, 8, 0);
    final now = DateTime(2026, 1, 25, 21, 30);
    final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
      stage: 0,
      scheduledAtLocal: scheduled,
      nowLocal: now,
      settings: settings,
    );
    expect(rolled.stage, 1);
    expect(rolled.nextReviewAtLocal, DateTime(2026, 1, 28, 8, 0));
  });

  test('stage1 missed -> stage2 weekly Sunday 21:00', () {
    final scheduled = DateTime(2026, 1, 28, 8, 0); // Wed
    final now = DateTime(2026, 1, 28, 22, 0);
    final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
      stage: 1,
      scheduledAtLocal: scheduled,
      nowLocal: now,
      settings: settings,
    );
    expect(rolled.stage, 2);
    expect(rolled.nextReviewAtLocal, DateTime(2026, 2, 1, 21, 0));
  });

  test('stage2 missed -> stays stage2 and advances by a week', () {
    final scheduled = DateTime(2026, 2, 1, 21, 0); // Sunday
    final now = DateTime(2026, 2, 1, 21, 30);
    final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
      stage: 2,
      scheduledAtLocal: scheduled,
      nowLocal: now,
      settings: settings,
    );
    expect(rolled.stage, 2);
    expect(rolled.nextReviewAtLocal, DateTime(2026, 2, 8, 21, 0));
  });
}
