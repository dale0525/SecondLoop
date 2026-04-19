import 'package:flutter/widgets.dart';

import 'temporal_locale_plugin.dart';
import 'temporal_resolution.dart';

final class ZhCnTemporalLocalePlugin implements TemporalLocalePlugin {
  static final Map<int, DateTime> _lunarNewYearDay = <int, DateTime>{
    2026: DateTime(2026, 2, 17),
  };

  static final Map<int, DateTime> _firstWorkingDayAfterFestival =
      <int, DateTime>{
    2026: DateTime(2026, 2, 24),
  };

  @override
  bool supports(Locale locale) =>
      locale.languageCode.toLowerCase() == 'zh' &&
      (locale.countryCode?.toUpperCase() ?? 'CN') == 'CN';

  @override
  TemporalCandidate? resolve(TemporalPluginRequest request) {
    final text = request.normalizedText;
    final year = request.nowLocal.year;
    final newYearDay = _lunarNewYearDay[year];
    final firstWorkingDay = _firstWorkingDayAfterFestival[year];
    if (newYearDay == null || firstWorkingDay == null) {
      return null;
    }

    final metadata = TemporalMetadata(
      inferredCalendarSystem: 'chinese_lunar',
      normalizedExpression: request.normalizedText,
    );

    if (text.contains('年初一之后第一个工作日') ||
        text.contains('年初一后第一个工作日') ||
        text.contains('节后第一个工作日')) {
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.94,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: firstWorkingDay,
        metadata: metadata,
      );
    }

    if (text.contains('年初一')) {
      return TemporalCandidate(
        resolver: TemporalResolver.localePlugin,
        confidence: 0.92,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: newYearDay,
        metadata: metadata,
      );
    }

    if (text.contains('春节后')) {
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
}
