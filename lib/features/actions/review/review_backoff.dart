import 'package:flutter/material.dart';

import '../settings/actions_settings_store.dart';

class ReviewAdvance {
  const ReviewAdvance({
    required this.stage,
    required this.nextReviewAtLocal,
  });

  final int stage;
  final DateTime nextReviewAtLocal;
}

DateTime _atTime(DateTime dayLocal, TimeOfDay time) {
  return DateTime(
    dayLocal.year,
    dayLocal.month,
    dayLocal.day,
    time.hour,
    time.minute,
  );
}

DateTime _endOfDay(DateTime dayLocal, TimeOfDay dayEnd) =>
    _atTime(dayLocal, dayEnd);

DateTime _nextWeekdayAtTime(DateTime fromLocal, int weekday, TimeOfDay time) {
  final base = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
  final deltaDays = (weekday - base.weekday) % 7;
  final candidateDay = base.add(Duration(days: deltaDays));
  final candidate = _atTime(candidateDay, time);
  if (!candidate.isAfter(fromLocal)) {
    final nextWeek = candidateDay.add(const Duration(days: 7));
    return _atTime(nextWeek, time);
  }
  return candidate;
}

class ReviewBackoff {
  static DateTime initialNextReviewAt(
      DateTime nowLocal, ActionsSettings settings) {
    final tomorrow = DateTime(nowLocal.year, nowLocal.month, nowLocal.day)
        .add(const Duration(days: 1));
    return _atTime(tomorrow, settings.morningTime);
  }

  static ReviewAdvance advanceAfterMissed({
    required int stage,
    required DateTime scheduledAtLocal,
    required ActionsSettings settings,
  }) {
    if (stage <= 0) {
      final baseDay = DateTime(
          scheduledAtLocal.year, scheduledAtLocal.month, scheduledAtLocal.day);
      final next =
          _atTime(baseDay.add(const Duration(days: 3)), settings.morningTime);
      return ReviewAdvance(stage: 1, nextReviewAtLocal: next);
    }

    if (stage == 1) {
      final next = _nextWeekdayAtTime(
        scheduledAtLocal,
        settings.weeklyReviewWeekday,
        settings.weeklyReviewTime,
      );
      return ReviewAdvance(stage: 2, nextReviewAtLocal: next);
    }

    final next = _nextWeekdayAtTime(
      scheduledAtLocal,
      settings.weeklyReviewWeekday,
      settings.weeklyReviewTime,
    );
    return ReviewAdvance(stage: stage, nextReviewAtLocal: next);
  }

  static ReviewAdvance rollForwardUntilDueOrFuture({
    required int stage,
    required DateTime scheduledAtLocal,
    required DateTime nowLocal,
    required ActionsSettings settings,
  }) {
    var currentStage = stage;
    var nextLocal = scheduledAtLocal;
    while (nowLocal.isAfter(_endOfDay(nextLocal, settings.dayEndTime))) {
      final advanced = advanceAfterMissed(
        stage: currentStage,
        scheduledAtLocal: nextLocal,
        settings: settings,
      );
      currentStage = advanced.stage;
      nextLocal = advanced.nextReviewAtLocal;
    }
    return ReviewAdvance(stage: currentStage, nextReviewAtLocal: nextLocal);
  }
}
