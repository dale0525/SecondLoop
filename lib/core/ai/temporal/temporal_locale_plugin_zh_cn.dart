import 'package:flutter/widgets.dart';

import 'temporal_locale_plugin.dart';
import 'temporal_resolution.dart';

final class ZhCnTemporalLocalePlugin implements TemporalLocalePlugin {
  static const Set<String> _nonSpringFestivalHolidayTokens = <String>{
    '国庆',
    '國慶',
    '中秋',
    '端午',
    '劳动节',
    '勞動節',
    '五一',
    '元旦',
    '清明',
    '圣诞',
    '聖誕',
  };
  static final Map<int, DateTime> _lunarNewYearDay = <int, DateTime>{
    2024: DateTime(2024, 2, 10),
    2025: DateTime(2025, 1, 29),
    2026: DateTime(2026, 2, 17),
    2027: DateTime(2027, 2, 6),
    2028: DateTime(2028, 1, 26),
    2029: DateTime(2029, 2, 13),
    2030: DateTime(2030, 2, 3),
  };
  static final Map<int, DateTime> _springFestivalFirstWorkingDay =
      <int, DateTime>{
    2026: DateTime(2026, 2, 24),
    2027: DateTime(2027, 2, 15),
  };

  @override
  bool supports(Locale locale) =>
      locale.languageCode.toLowerCase() == 'zh' &&
      (locale.countryCode?.toUpperCase() ?? 'CN') == 'CN';

  @override
  TemporalCandidate? resolve(TemporalPluginRequest request) {
    final text = request.normalizedText;
    const metadata = TemporalMetadata(
      inferredCalendarSystem: 'chinese_lunar',
    );
    final isFirstWorkingDayExpression = text.contains('年初一之后第一个工作日') ||
        text.contains('年初一后第一个工作日') ||
        text.contains('节后第一个工作日');

    if (isFirstWorkingDayExpression) {
      final matchedExpression = _matchedExpression(text);
      if (_containsExplicitNonSpringFestivalHoliday(text)) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0,
          semantics: TemporalSemantics.none,
          metadata: metadata.copyWith(
            needsEnhancement: true,
            normalizedExpression: matchedExpression,
          ),
        );
      }
      final firstWorkingDay = _resolveFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: true,
      );
      if (firstWorkingDay == null) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0,
          semantics: TemporalSemantics.none,
          metadata: metadata.copyWith(
            needsEnhancement: true,
            normalizedExpression: matchedExpression,
          ),
        );
      }
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.94,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: firstWorkingDay,
        metadata: metadata.copyWith(normalizedExpression: matchedExpression),
      );
    }

    if (text.contains('年初一')) {
      const matchedExpression = '年初一';
      final newYearDay = _resolveFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: false,
      );
      if (newYearDay == null) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0,
          semantics: TemporalSemantics.none,
          metadata: metadata.copyWith(
            needsEnhancement: true,
            normalizedExpression: matchedExpression,
          ),
        );
      }
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.92,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: newYearDay,
        metadata: metadata.copyWith(normalizedExpression: matchedExpression),
      );
    }

    if (text.contains('春节后')) {
      const matchedExpression = '春节后';
      if (request.mode != TemporalMode.retrievalWindow) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0,
          semantics: TemporalSemantics.none,
          metadata: metadata.copyWith(
            normalizedExpression: matchedExpression,
            needsEnhancement: true,
          ),
        );
      }
      final firstWorkingDay = _resolveFestivalBoundary(
        request.nowLocal,
        useFirstWorkingDay: true,
        preferPastIfAvailable: true,
      );
      if (firstWorkingDay == null) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0,
          semantics: TemporalSemantics.none,
          metadata: metadata.copyWith(
            needsEnhancement: true,
            normalizedExpression: matchedExpression,
          ),
        );
      }
      final today = DateTime(
        request.nowLocal.year,
        request.nowLocal.month,
        request.nowLocal.day,
      );
      if (!firstWorkingDay.isAfter(today)) {
        return TemporalCandidate(
          resolver: TemporalResolver.localePlugin,
          confidence: 0.82,
          semantics: TemporalSemantics.rangePast,
          pointLocal: firstWorkingDay,
          startLocal: firstWorkingDay,
          endLocal: request.nowLocal,
          metadata: metadata.copyWith(normalizedExpression: matchedExpression),
        );
      }
      final nextBoundary = _resolveNextFestivalBoundary(
            firstWorkingDay,
            useFirstWorkingDay: true,
          ) ??
          firstWorkingDay.add(const Duration(days: 366));
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.82,
        semantics: TemporalSemantics.rangeFuture,
        pointLocal: firstWorkingDay,
        startLocal: firstWorkingDay,
        endLocal: nextBoundary,
        metadata: metadata.copyWith(normalizedExpression: matchedExpression),
      );
    }

    return null;
  }

  @override
  bool needsEnhancement(TemporalPluginRequest request) {
    final text = request.normalizedText;
    if (!(text.contains('年初一之后第一个工作日') ||
        text.contains('年初一后第一个工作日') ||
        text.contains('节后第一个工作日') ||
        text.contains('年初一') ||
        text.contains('春节后'))) {
      return false;
    }
    if (_containsExplicitNonSpringFestivalHoliday(text)) {
      return true;
    }
    if (text.contains('春节后') && request.mode != TemporalMode.retrievalWindow) {
      return true;
    }
    return _resolveFestivalBoundary(
          request.nowLocal,
          useFirstWorkingDay: text.contains('年初一之后第一个工作日') ||
              text.contains('年初一后第一个工作日') ||
              text.contains('节后第一个工作日'),
          preferPastIfAvailable: text.contains('春节后'),
        ) ==
        null;
  }

  static DateTime? _resolveFestivalBoundary(
    DateTime nowLocal, {
    required bool useFirstWorkingDay,
    bool preferPastIfAvailable = false,
  }) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final boundaries =
        useFirstWorkingDay ? _springFestivalFirstWorkingDay : _lunarNewYearDay;
    if (boundaries.isEmpty) return null;

    final years = boundaries.keys.toList()..sort();
    final maxSupportedYear = years.last;
    if (today.year > maxSupportedYear) {
      return null;
    }
    DateTime? mostRecent;
    DateTime? upcoming;
    for (final year in years) {
      final candidate = boundaries[year];
      if (candidate == null) continue;
      if (!candidate.isAfter(today)) {
        mostRecent = candidate;
      }
      if (upcoming == null && !candidate.isBefore(today)) {
        upcoming = candidate;
        if (!preferPastIfAvailable) {
          return upcoming;
        }
      }
    }
    if (!preferPastIfAvailable) {
      return upcoming;
    }
    if (mostRecent != null && mostRecent.year == today.year) {
      return mostRecent;
    }
    return upcoming;
  }

  static DateTime? _resolveNextFestivalBoundary(
    DateTime boundary, {
    required bool useFirstWorkingDay,
  }) {
    final boundaries =
        useFirstWorkingDay ? _springFestivalFirstWorkingDay : _lunarNewYearDay;
    if (boundaries.isEmpty) return null;

    final years = boundaries.keys.toList()..sort();
    for (final year in years) {
      final candidate = boundaries[year];
      if (candidate == null) continue;
      if (candidate.isAfter(boundary)) {
        return candidate;
      }
    }
    return null;
  }

  static String _matchedExpression(String text) {
    if (text.contains('年初一之后第一个工作日')) {
      return '年初一之后第一个工作日';
    }
    if (text.contains('年初一后第一个工作日')) {
      return '年初一后第一个工作日';
    }
    if (text.contains('节后第一个工作日')) {
      return '节后第一个工作日';
    }
    if (text.contains('年初一')) {
      return '年初一';
    }
    if (text.contains('春节后')) {
      return '春节后';
    }
    return text;
  }

  static bool _containsExplicitNonSpringFestivalHoliday(String text) {
    if (text.contains('春节') || text.contains('春節') || text.contains('年初一')) {
      return false;
    }
    for (final token in _nonSpringFestivalHolidayTokens) {
      if (text.contains(token)) {
        return true;
      }
    }
    return false;
  }
}
