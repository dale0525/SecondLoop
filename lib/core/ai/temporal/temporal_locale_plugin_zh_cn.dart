import 'package:flutter/widgets.dart';

import 'temporal_locale_plugin.dart';
import 'temporal_resolution.dart';

final class ZhCnTemporalLocalePlugin implements TemporalLocalePlugin {
  static final Map<int, DateTime> _lunarNewYearDay = <int, DateTime>{
    2024: DateTime(2024, 2, 10),
    2025: DateTime(2025, 1, 29),
    2026: DateTime(2026, 2, 17),
    2027: DateTime(2027, 2, 6),
    2028: DateTime(2028, 1, 26),
    2029: DateTime(2029, 2, 13),
    2030: DateTime(2030, 2, 3),
  };

  @override
  bool supports(Locale locale) =>
      locale.languageCode.toLowerCase() == 'zh' &&
      (locale.countryCode?.toUpperCase() ?? 'CN') == 'CN';

  @override
  TemporalCandidate? resolve(TemporalPluginRequest request) {
    final text = request.normalizedText;
    final metadata = TemporalMetadata(
      inferredCalendarSystem: 'chinese_lunar',
      normalizedExpression: request.normalizedText,
    );

    if (text.contains('年初一之后第一个工作日') ||
        text.contains('年初一后第一个工作日') ||
        text.contains('节后第一个工作日')) {
      final firstWorkingDay = _resolveNextFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: true,
      );
      if (firstWorkingDay == null) return null;
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.94,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: firstWorkingDay,
        metadata: metadata,
      );
    }

    if (text.contains('年初一')) {
      final newYearDay = _resolveNextFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: false,
      );
      if (newYearDay == null) return null;
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.92,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: newYearDay,
        metadata: metadata,
      );
    }

    if (text.contains('春节后')) {
      final firstWorkingDay = _resolveNextFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: true,
      );
      if (firstWorkingDay == null) return null;
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.82,
        semantics: TemporalSemantics.rangeFuture,
        startLocal: firstWorkingDay,
        endLocal: firstWorkingDay.add(const Duration(days: 7)),
        metadata: metadata,
      );
    }

    return null;
  }

  static DateTime? _resolveNextFestivalBoundary(
    DateTime nowLocal, {
    required bool useFirstWorkingDay,
  }) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final years = _lunarNewYearDay.keys.toList()..sort();
    for (final year in years) {
      final newYearDay = _lunarNewYearDay[year];
      if (newYearDay == null) continue;
      final candidate = useFirstWorkingDay
          ? _firstWorkingDayAfterFestival(newYearDay)
          : newYearDay;
      if (!candidate.isBefore(today)) {
        return candidate;
      }
    }
    return null;
  }

  static DateTime _firstWorkingDayAfterFestival(DateTime newYearDay) {
    var candidate = newYearDay.add(const Duration(days: 7));
    while (candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
