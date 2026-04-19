import 'package:flutter/widgets.dart';

import '../../../core/ai/temporal/temporal_engine.dart';
import '../../../core/ai/temporal/temporal_resolution.dart';

class LocalTimeRangeResolution {
  const LocalTimeRangeResolution({
    required this.kind,
    required this.matchedText,
    required this.startLocal,
    required this.endLocal,
  });

  final String kind;
  final String matchedText;
  final DateTime startLocal;
  final DateTime endLocal;
}

class LocalTimeRangeResolver {
  static LocalTimeRangeResolution? resolve(
    String text,
    DateTime nowLocal, {
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final resolution = TemporalEngine.resolve(
      text: raw,
      nowLocal: nowLocal,
      locale: locale,
      timezone: '',
      firstDayOfWeek: firstDayOfWeekIndex,
      mode: TemporalMode.retrievalWindow,
      allowEnhancement: false,
    );
    if (resolution.startLocal == null || resolution.endLocal == null) {
      return null;
    }
    final kind = switch (resolution.metadata.normalizedExpression) {
      final value? when value.contains('上周') || value.contains('last week') =>
        'last_week',
      final value? when value.contains('本周') || value.contains('this week') =>
        'this_week',
      final value? when value.contains('今天') || value.contains('today') =>
        'today',
      final value? when value.contains('明天') || value.contains('tomorrow') =>
        'tomorrow',
      final value? when value.contains('昨天') || value.contains('yesterday') =>
        'yesterday',
      _ => 'time_window',
    };
    return LocalTimeRangeResolution(
      kind: kind,
      matchedText: raw,
      startLocal: resolution.startLocal!,
      endLocal: resolution.endLocal!,
    );
  }
}
