import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActionsSettings {
  const ActionsSettings({
    required this.morningTime,
    required this.dayEndTime,
    required this.weeklyReviewTime,
    this.weeklyReviewWeekday = DateTime.sunday,
  });

  final TimeOfDay morningTime;
  final TimeOfDay dayEndTime;
  final TimeOfDay weeklyReviewTime;
  final int weeklyReviewWeekday;

  int get morningMinutes => morningTime.hour * 60 + morningTime.minute;
  int get dayEndMinutes => dayEndTime.hour * 60 + dayEndTime.minute;
  int get weeklyReviewMinutes =>
      weeklyReviewTime.hour * 60 + weeklyReviewTime.minute;
}

class ActionsSettingsStore {
  static const _kMorningMinutesKey = 'actions.review.morning_minutes_v1';
  static const _kDayEndMinutesKey = 'actions.review.day_end_minutes_v1';
  static const _kWeeklyMinutesKey = 'actions.review.weekly_minutes_v1';
  static const _kWeeklyWeekdayKey = 'actions.review.weekly_weekday_v1';

  static const _defaultMorningMinutes = 8 * 60;
  static const _defaultDayEndMinutes = 21 * 60;

  static TimeOfDay _timeOfDayFromMinutes(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static Future<ActionsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final morningMinutes =
        prefs.getInt(_kMorningMinutesKey) ?? _defaultMorningMinutes;
    final dayEndMinutes =
        prefs.getInt(_kDayEndMinutesKey) ?? _defaultDayEndMinutes;
    final weeklyMinutes =
        prefs.getInt(_kWeeklyMinutesKey) ?? _defaultDayEndMinutes;
    final weeklyWeekday = prefs.getInt(_kWeeklyWeekdayKey) ?? DateTime.sunday;
    return ActionsSettings(
      morningTime: _timeOfDayFromMinutes(morningMinutes),
      dayEndTime: _timeOfDayFromMinutes(dayEndMinutes),
      weeklyReviewTime: _timeOfDayFromMinutes(weeklyMinutes),
      weeklyReviewWeekday: weeklyWeekday,
    );
  }

  static Future<void> setMorningTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMorningMinutesKey, value.hour * 60 + value.minute);
  }

  static Future<void> setDayEndTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDayEndMinutesKey, value.hour * 60 + value.minute);
  }

  static Future<void> setWeeklyReviewTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWeeklyMinutesKey, value.hour * 60 + value.minute);
  }
}
