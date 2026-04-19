import 'package:flutter/widgets.dart';

import 'temporal_resolution.dart';

final class TemporalRuleResolver {
  static final RegExp _isoDate = RegExp(
    r'\b(\d{4})\s*[-‐‑–—−－]\s*(\d{1,2})\s*[-‐‑–—−－]\s*(\d{1,2})\b',
  );
  static final RegExp _slashDate =
      RegExp(r'\b(\d{1,2})\s*[\/／]\s*(\d{1,2})(?:\s*[\/／]\s*(\d{2,4}))?\b');
  static final RegExp _cjkMonthDay = RegExp(
    r'(?<!\d)(\d{1,2})\s*(?:月|월)\s*(\d{1,2})\s*(?:日|号|號|일)(?!\d)',
  );
  static final RegExp _time24h =
      RegExp(r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)');
  static final RegExp _timeAmPm = RegExp(
      r'(?<!\d)(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false);
  static final RegExp _zhMeridiemTime = RegExp(
    r'(上午|早上|凌晨|中午|下午|晚上|今晚|今夜|夜里|夜晚)\s*(\d{1,2})(?:[:：](\d{2}))?\s*(?:点|點|时|時)?(?:\s*(半))?',
  );

  static final List<MapEntry<String, int>> _relativeDayTokens =
      _sortStringIntEntriesByLength(<MapEntry<String, int>>[
    const MapEntry<String, int>('day after tomorrow', 2),
    const MapEntry<String, int>('after tomorrow', 2),
    const MapEntry<String, int>('pasado mañana', 2),
    const MapEntry<String, int>('après-demain', 2),
    const MapEntry<String, int>('übermorgen', 2),
    const MapEntry<String, int>('明後日', 2),
    const MapEntry<String, int>('모레', 2),
    const MapEntry<String, int>('大后天', 3),
    const MapEntry<String, int>('大後天', 3),
    const MapEntry<String, int>('tomorrow morning', 1),
    const MapEntry<String, int>('mañana por la mañana', 1),
    const MapEntry<String, int>('demain matin', 1),
    const MapEntry<String, int>('morgen früh', 1),
    const MapEntry<String, int>('明日の朝', 1),
    const MapEntry<String, int>('내일 아침', 1),
    const MapEntry<String, int>('明早', 1),
    const MapEntry<String, int>('明晨', 1),
    const MapEntry<String, int>('tomorrow', 1),
    const MapEntry<String, int>('today', 0),
    const MapEntry<String, int>('yesterday', -1),
    const MapEntry<String, int>('mañana', 1),
    const MapEntry<String, int>('hoy', 0),
    const MapEntry<String, int>('ayer', -1),
    const MapEntry<String, int>('demain', 1),
    const MapEntry<String, int>("aujourd'hui", 0),
    const MapEntry<String, int>('hier', -1),
    const MapEntry<String, int>('morgen', 1),
    const MapEntry<String, int>('heute abend', 0),
    const MapEntry<String, int>('heute', 0),
    const MapEntry<String, int>('gestern', -1),
    const MapEntry<String, int>('ce soir', 0),
    const MapEntry<String, int>('esta noche', 0),
    const MapEntry<String, int>('tonight', 0),
    const MapEntry<String, int>('今天', 0),
    const MapEntry<String, int>('今晚', 0),
    const MapEntry<String, int>('明天', 1),
    const MapEntry<String, int>('昨天', -1),
    const MapEntry<String, int>('后天', 2),
    const MapEntry<String, int>('後天', 2),
    const MapEntry<String, int>('今日', 0),
    const MapEntry<String, int>('今夜', 0),
    const MapEntry<String, int>('明日', 1),
    const MapEntry<String, int>('昨日', -1),
    const MapEntry<String, int>('今日の夜', 0),
    const MapEntry<String, int>('오늘 밤', 0),
    const MapEntry<String, int>('오늘', 0),
    const MapEntry<String, int>('내일', 1),
    const MapEntry<String, int>('어제', -1),
  ]);

  static final List<
          ({String token, int offsetWeeks, TemporalSemantics semantics})>
      _weekTokens = _sortWeekTokensByLength(<({
    String token,
    int offsetWeeks,
    TemporalSemantics semantics
  })>[
    (
      token: '上周',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: '上週',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: 'last week',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: '上星期',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: '先週',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: '지난주',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: 'la semaine dernière',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: 'letzte woche',
      offsetWeeks: -1,
      semantics: TemporalSemantics.rangePast,
    ),
    (
      token: '本周',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '本週',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: 'this week',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '这周',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '這週',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '这星期',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '這星期',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '今週',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '이번 주',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: 'esta semana',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: 'cette semaine',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: 'diese woche',
      offsetWeeks: 0,
      semantics: TemporalSemantics.rangeBoth,
    ),
    (
      token: '下周',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: '下週',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: 'next week',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: '下星期',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: '来週',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: '다음 주',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: 'próxima semana',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: 'la semaine prochaine',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
    (
      token: 'nächste woche',
      offsetWeeks: 1,
      semantics: TemporalSemantics.rangeFuture,
    ),
  ]);

  static final List<({int weekday, List<String> tokens})> _weekdayTokens = [
    (
      weekday: DateTime.monday,
      tokens: _sortStringsByLength(<String>[
        '周一',
        '週一',
        '星期一',
        '礼拜一',
        '禮拜一',
        'monday',
        '月曜',
        '月曜日',
        '월요일',
        'lunes',
        'lundi',
        'montag',
      ]),
    ),
    (
      weekday: DateTime.tuesday,
      tokens: _sortStringsByLength(<String>[
        '周二',
        '週二',
        '星期二',
        '礼拜二',
        '禮拜二',
        'tuesday',
        '火曜',
        '火曜日',
        '화요일',
        'martes',
        'mardi',
        'dienstag',
      ]),
    ),
    (
      weekday: DateTime.wednesday,
      tokens: _sortStringsByLength(<String>[
        '周三',
        '週三',
        '星期三',
        '礼拜三',
        '禮拜三',
        'wednesday',
        '水曜',
        '水曜日',
        '수요일',
        'miércoles',
        'miercoles',
        'mercredi',
        'mittwoch',
      ]),
    ),
    (
      weekday: DateTime.thursday,
      tokens: _sortStringsByLength(<String>[
        '周四',
        '週四',
        '星期四',
        '礼拜四',
        '禮拜四',
        'thursday',
        '木曜',
        '木曜日',
        '목요일',
        'jueves',
        'jeudi',
        'donnerstag',
      ]),
    ),
    (
      weekday: DateTime.friday,
      tokens: _sortStringsByLength(<String>[
        '周五',
        '週五',
        '星期五',
        '礼拜五',
        '禮拜五',
        'friday',
        '金曜',
        '金曜日',
        '금요일',
        'viernes',
        'vendredi',
        'freitag',
      ]),
    ),
    (
      weekday: DateTime.saturday,
      tokens: _sortStringsByLength(<String>[
        '周六',
        '週六',
        '星期六',
        '礼拜六',
        '禮拜六',
        'saturday',
        '土曜',
        '土曜日',
        '토요일',
        'sábado',
        'sabado',
        'samedi',
        'samstag',
        'sonnabend',
      ]),
    ),
    (
      weekday: DateTime.sunday,
      tokens: _sortStringsByLength(<String>[
        '周日',
        '週日',
        '周天',
        '週天',
        '星期日',
        '星期天',
        '礼拜日',
        '礼拜天',
        '禮拜日',
        '禮拜天',
        'sunday',
        '日曜',
        '日曜日',
        '일요일',
        'domingo',
        'dimanche',
        'sonntag',
      ]),
    ),
  ];

  static const Set<String> _monthStartTokens = <String>{
    '月初',
    'month start',
  };

  static const Set<String> _monthEndTokens = <String>{
    '月底',
    'month end',
  };

  static const Set<String> _yearEndTokens = <String>{
    '年底',
    'year end',
  };

  static const Map<String, ({int month, int day})> _fixedHolidays =
      <String, ({int month, int day})>{
    '圣诞节': (month: 12, day: 25),
    'christmas': (month: 12, day: 25),
  };

  static String normalize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFF10 + 0x30);
        continue;
      }
      switch (rune) {
        case 0xFF1A:
          buffer.write(':');
          continue;
        case 0xFF0F:
          buffer.write('/');
          continue;
        case 0x3000:
          buffer.write(' ');
          continue;
      }
      buffer.writeCharCode(rune);
    }

    return buffer
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[，,。！？!?.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static TemporalCandidate? resolve({
    required String text,
    required String normalizedText,
    required DateTime nowLocal,
    required Locale locale,
    required int firstDayOfWeek,
    required TemporalMode mode,
  }) {
    if (normalizedText.isEmpty) return null;

    final timeOfDay = _parseTimeOfDay(text);

    final explicitDateCandidate = _resolveExplicitDate(
      text: text,
      normalizedText: normalizedText,
      nowLocal: nowLocal,
      timeOfDay: timeOfDay,
      preferFuture: mode != TemporalMode.retrievalWindow,
    );
    if (explicitDateCandidate != null) {
      return explicitDateCandidate;
    }

    final weekScopedWeekday = _resolveWeekScopedWeekday(
      normalizedText: normalizedText,
      nowLocal: nowLocal,
      firstDayOfWeek: firstDayOfWeek,
      timeOfDay: timeOfDay,
    );
    if (weekScopedWeekday != null) {
      return weekScopedWeekday;
    }

    final weekCandidate = _resolveWeekRange(
      normalizedText: normalizedText,
      nowLocal: nowLocal,
      firstDayOfWeek: firstDayOfWeek,
    );
    if (weekCandidate != null) {
      return weekCandidate;
    }

    final relativeDay = _matchRelativeDay(normalizedText);
    if (relativeDay != null) {
      final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      final day = base.add(Duration(days: relativeDay.value));
      final point = timeOfDay == null
          ? day
          : DateTime(
              day.year,
              day.month,
              day.day,
              timeOfDay.hour,
              timeOfDay.minute,
            );
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.94,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: point,
        hasExplicitTime: timeOfDay != null,
        metadata: TemporalMetadata(
          inferredTimeOfDay: timeOfDay?.label,
          normalizedExpression: relativeDay.key,
        ),
      );
    }

    final weekday = _matchWeekday(normalizedText);
    if (weekday != null) {
      final next = _nextWeekdayOnOrAfter(nowLocal, weekday.weekday);
      var point = DateTime(next.year, next.month, next.day);
      if (timeOfDay != null) {
        point = DateTime(
          point.year,
          point.month,
          point.day,
          timeOfDay.hour,
          timeOfDay.minute,
        );
      }
      if (timeOfDay != null && point.isBefore(nowLocal)) {
        point = point.add(const Duration(days: 7));
      }
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.89,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: point,
        hasExplicitTime: timeOfDay != null,
        projectedRollForwardDays: timeOfDay == null ? 7 : 0,
        metadata: TemporalMetadata(
          inferredTimeOfDay: timeOfDay?.label,
          normalizedExpression: weekday.token,
        ),
      );
    }

    final monthStartToken = _matchToken(normalizedText, _monthStartTokens);
    if (monthStartToken != null) {
      final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      final candidateDay = DateTime(nowLocal.year, nowLocal.month, 1);
      final resolved = candidateDay.isBefore(today)
          ? DateTime(nowLocal.year, nowLocal.month + 1, 1)
          : candidateDay;
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.9,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: resolved,
        metadata: TemporalMetadata(normalizedExpression: monthStartToken),
      );
    }

    final monthEndToken = _matchToken(normalizedText, _monthEndTokens);
    if (monthEndToken != null) {
      final candidateDay = _lastDayOfMonth(nowLocal.year, nowLocal.month);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.9,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: resolved,
        metadata: TemporalMetadata(normalizedExpression: monthEndToken),
      );
    }

    final yearEndToken = _matchToken(normalizedText, _yearEndTokens);
    if (yearEndToken != null) {
      final candidateDay = DateTime(nowLocal.year, 12, 31);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.88,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: resolved,
        metadata: TemporalMetadata(normalizedExpression: yearEndToken),
      );
    }

    for (final entry in _fixedHolidays.entries) {
      if (!normalizedText.contains(entry.key.toLowerCase())) continue;
      final md = entry.value;
      final candidateDay = DateTime(nowLocal.year, md.month, md.day);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.9,
        semantics: TemporalSemantics.pointInTime,
        pointLocal: resolved,
        metadata: TemporalMetadata(normalizedExpression: entry.key),
      );
    }

    if (timeOfDay != null) {
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.45,
        semantics: TemporalSemantics.pointInTime,
        metadata: TemporalMetadata(
          inferredTimeOfDay: timeOfDay.label,
          ambiguous: true,
          normalizedExpression: timeOfDay.matchedText,
        ),
      );
    }

    return null;
  }

  static TemporalCandidate? _resolveWeekScopedWeekday({
    required String normalizedText,
    required DateTime nowLocal,
    required int firstDayOfWeek,
    required _TemporalTimeOfDay? timeOfDay,
  }) {
    final scopedWeekday = _matchWeekScopedWeekday(normalizedText);
    if (scopedWeekday == null) return null;

    final thisWeekStart = _startOfWeek(nowLocal, firstDayOfWeek);
    final weekStart = thisWeekStart.add(
      Duration(days: scopedWeekday.offsetWeeks * 7),
    );
    final firstWeekday = _firstWeekdayFromIndex(firstDayOfWeek);
    final weekdayOffset = (scopedWeekday.weekday - firstWeekday + 7) % 7;
    final day = weekStart.add(Duration(days: weekdayOffset));
    final point = timeOfDay == null
        ? day
        : DateTime(
            day.year,
            day.month,
            day.day,
            timeOfDay.hour,
            timeOfDay.minute,
          );
    return TemporalCandidate(
      resolver: TemporalResolver.rule,
      confidence: 0.93,
      semantics: TemporalSemantics.pointInTime,
      pointLocal: point,
      hasExplicitTime: timeOfDay != null,
      metadata: TemporalMetadata(
        inferredTimeOfDay: timeOfDay?.label,
        normalizedExpression: scopedWeekday.token,
      ),
    );
  }

  static TemporalCandidate? _resolveExplicitDate({
    required String text,
    required String normalizedText,
    required DateTime nowLocal,
    required _TemporalTimeOfDay? timeOfDay,
    required bool preferFuture,
  }) {
    final isoMatch = _isoDate.firstMatch(normalizedText);
    if (isoMatch != null) {
      final year = int.tryParse(isoMatch.group(1)!);
      final month = int.tryParse(isoMatch.group(2)!);
      final day = int.tryParse(isoMatch.group(3)!);
      if (_isValidDate(year, month, day)) {
        final point = _composePoint(year!, month!, day!, timeOfDay);
        return TemporalCandidate(
          resolver: TemporalResolver.rule,
          confidence: 0.98,
          semantics: TemporalSemantics.pointInTime,
          pointLocal: point,
          hasExplicitTime: timeOfDay != null,
          metadata: TemporalMetadata(
            inferredTimeOfDay: timeOfDay?.label,
            normalizedExpression: isoMatch.group(0),
          ),
        );
      }
    }

    final slashMatch = _slashDate.firstMatch(normalizedText);
    if (slashMatch != null) {
      final month = int.tryParse(slashMatch.group(1)!);
      final day = int.tryParse(slashMatch.group(2)!);
      final rawYear = slashMatch.group(3);
      if (month != null && day != null) {
        final year = rawYear == null
            ? _resolveYearForMonthDay(
                nowLocal,
                month,
                day,
                preferFuture: preferFuture,
              )
            : rawYear.length == 2
                ? 2000 + int.parse(rawYear)
                : int.parse(rawYear);
        if (_isValidDate(year, month, day)) {
          return TemporalCandidate(
            resolver: TemporalResolver.rule,
            confidence: 0.97,
            semantics: TemporalSemantics.pointInTime,
            pointLocal: _composePoint(year, month, day, timeOfDay),
            hasExplicitTime: timeOfDay != null,
            metadata: TemporalMetadata(
              inferredTimeOfDay: timeOfDay?.label,
              normalizedExpression: slashMatch.group(0),
            ),
          );
        }
      }
    }

    final cjkMatch = _cjkMonthDay.firstMatch(text);
    if (cjkMatch != null) {
      final month = int.tryParse(cjkMatch.group(1)!);
      final day = int.tryParse(cjkMatch.group(2)!);
      if (month != null && day != null) {
        final year = _resolveYearForMonthDay(
          nowLocal,
          month,
          day,
          preferFuture: preferFuture,
        );
        if (_isValidDate(year, month, day)) {
          return TemporalCandidate(
            resolver: TemporalResolver.rule,
            confidence: 0.97,
            semantics: TemporalSemantics.pointInTime,
            pointLocal: _composePoint(year, month, day, timeOfDay),
            hasExplicitTime: timeOfDay != null,
            metadata: TemporalMetadata(
              inferredTimeOfDay: timeOfDay?.label,
              normalizedExpression: cjkMatch.group(0),
            ),
          );
        }
      }
    }

    return null;
  }

  static TemporalCandidate? _resolveWeekRange({
    required String normalizedText,
    required DateTime nowLocal,
    required int firstDayOfWeek,
  }) {
    for (final entry in _weekTokens) {
      if (!normalizedText.contains(entry.token.toLowerCase())) continue;
      final thisWeekStart = _startOfWeek(nowLocal, firstDayOfWeek);
      final start = thisWeekStart.add(Duration(days: entry.offsetWeeks * 7));
      final end = start.add(const Duration(days: 7));
      return TemporalCandidate(
        resolver: TemporalResolver.rule,
        confidence: 0.95,
        semantics: entry.semantics,
        startLocal: start,
        endLocal: end,
        metadata: TemporalMetadata(normalizedExpression: entry.token),
      );
    }
    return null;
  }

  static List<MapEntry<String, int>> _sortStringIntEntriesByLength(
    List<MapEntry<String, int>> entries,
  ) {
    final sorted = List<MapEntry<String, int>>.from(entries);
    sorted.sort((a, b) => b.key.length.compareTo(a.key.length));
    return sorted;
  }

  static List<({String token, int offsetWeeks, TemporalSemantics semantics})>
      _sortWeekTokensByLength(
    List<({String token, int offsetWeeks, TemporalSemantics semantics})> tokens,
  ) {
    final sorted = List<
        ({String token, int offsetWeeks, TemporalSemantics semantics})>.from(
      tokens,
    );
    sorted.sort((a, b) => b.token.length.compareTo(a.token.length));
    return sorted;
  }

  static List<String> _sortStringsByLength(List<String> tokens) {
    final sorted = List<String>.from(tokens);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }

  static MapEntry<String, int>? _matchRelativeDay(String normalizedText) {
    for (final entry in _relativeDayTokens) {
      if (normalizedText.contains(entry.key.toLowerCase())) {
        return entry;
      }
    }
    return null;
  }

  static ({String token, int weekday})? _matchWeekday(String normalizedText) {
    for (final entry in _weekdayTokens) {
      for (final token in entry.tokens) {
        if (normalizedText.contains(token.toLowerCase())) {
          return (token: token, weekday: entry.weekday);
        }
      }
    }
    return null;
  }

  static ({String token, int weekday, int offsetWeeks})?
      _matchWeekScopedWeekday(String normalizedText) {
    for (final week in _weekTokens) {
      final weekIndex = normalizedText.indexOf(week.token.toLowerCase());
      if (weekIndex == -1) continue;
      for (final weekdayEntry in _weekdayTokens) {
        for (final token in weekdayEntry.tokens) {
          final tokenIndex = normalizedText.indexOf(
            token.toLowerCase(),
            weekIndex + week.token.length,
          );
          if (tokenIndex == -1) continue;
          return (
            token: normalizedText.substring(
              weekIndex,
              tokenIndex + token.length,
            ),
            weekday: weekdayEntry.weekday,
            offsetWeeks: week.offsetWeeks,
          );
        }
      }
    }
    return null;
  }

  static String? _matchToken(String normalizedText, Set<String> tokens) {
    for (final token in tokens) {
      if (normalizedText.contains(token.toLowerCase())) return token;
    }
    return null;
  }

  static _TemporalTimeOfDay? _parseTimeOfDay(String text) {
    final match24 = _time24h.firstMatch(text);
    if (match24 != null) {
      final hour = int.tryParse(match24.group(1) ?? '');
      final minute = int.tryParse(match24.group(2) ?? '');
      if (hour != null && minute != null) {
        return _TemporalTimeOfDay(
          hour: hour,
          minute: minute,
          matchedText: match24.group(0)!,
          label: 'clock',
        );
      }
    }

    final matchAmPm = _timeAmPm.firstMatch(text.toLowerCase());
    if (matchAmPm != null) {
      final rawHour = int.tryParse(matchAmPm.group(1) ?? '');
      final minute = int.tryParse(matchAmPm.group(2) ?? '') ?? 0;
      final meridiem = matchAmPm.group(3)?.toLowerCase();
      if (rawHour != null && rawHour >= 1 && rawHour <= 12) {
        var hour = rawHour % 12;
        if (meridiem == 'pm') hour += 12;
        return _TemporalTimeOfDay(
          hour: hour,
          minute: minute,
          matchedText: matchAmPm.group(0)!,
          label: meridiem ?? 'clock',
        );
      }
    }

    final zhMatch = _zhMeridiemTime.firstMatch(text);
    if (zhMatch != null) {
      final meridiem = zhMatch.group(1) ?? '';
      final rawHour = int.tryParse(zhMatch.group(2) ?? '');
      final minute = zhMatch.group(4) != null
          ? 30
          : int.tryParse(zhMatch.group(3) ?? '') ?? 0;
      if (rawHour != null) {
        var hour = rawHour % 12;
        if (meridiem.contains('下午') ||
            meridiem.contains('晚上') ||
            meridiem.contains('今晚') ||
            meridiem.contains('今夜') ||
            meridiem.contains('夜')) {
          hour += 12;
        } else if (meridiem.contains('中午') && hour < 11) {
          hour += 12;
        }
        return _TemporalTimeOfDay(
          hour: hour,
          minute: minute,
          matchedText: zhMatch.group(0)!,
          label: meridiem,
        );
      }
    }

    return null;
  }

  static DateTime _composePoint(
    int year,
    int month,
    int day,
    _TemporalTimeOfDay? timeOfDay,
  ) {
    if (timeOfDay == null) {
      return DateTime(year, month, day);
    }
    return DateTime(year, month, day, timeOfDay.hour, timeOfDay.minute);
  }

  static bool _isValidDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return false;
    if (month < 1 || month > 12 || day < 1) return false;
    final endOfMonth = DateTime(year, month + 1, 0).day;
    return day <= endOfMonth;
  }

  static int _resolveYearForMonthDay(
    DateTime nowLocal,
    int month,
    int day, {
    required bool preferFuture,
  }) {
    final startOfToday = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final currentYear = DateTime(nowLocal.year, month, day);
    if (preferFuture) {
      if (!currentYear.isBefore(startOfToday)) {
        return nowLocal.year;
      }
      return nowLocal.year + 1;
    }
    if (!currentYear.isAfter(startOfToday)) {
      return nowLocal.year;
    }
    return nowLocal.year - 1;
  }

  static DateTime _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0);
  }

  static DateTime _nextOccurrence(DateTime candidateDay, DateTime nowLocal) {
    final startOfToday = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (!candidateDay.isBefore(startOfToday)) return candidateDay;
    if (candidateDay.month == 12 && candidateDay.day == 31) {
      return DateTime(candidateDay.year + 1, 12, 31);
    }
    if (candidateDay.day == 1 && candidateDay.month == 1) {
      return DateTime(candidateDay.year + 1, 1, 1);
    }
    if (candidateDay.day == 1) {
      return DateTime(candidateDay.year, candidateDay.month + 1, 1);
    }
    return DateTime(
        candidateDay.year + 1, candidateDay.month, candidateDay.day);
  }

  static DateTime _startOfWeek(DateTime nowLocal, int firstDayOfWeek) {
    final firstWeekday = _firstWeekdayFromIndex(firstDayOfWeek);
    final diff = (nowLocal.weekday - firstWeekday + 7) % 7;
    final start = nowLocal.subtract(Duration(days: diff));
    return DateTime(start.year, start.month, start.day);
  }

  static int _firstWeekdayFromIndex(int firstDayOfWeekIndex) {
    if (firstDayOfWeekIndex == 0) return DateTime.sunday;
    return firstDayOfWeekIndex.clamp(DateTime.monday, DateTime.saturday);
  }

  static DateTime _nextWeekdayOnOrAfter(DateTime nowLocal, int targetWeekday) {
    final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final delta = (targetWeekday - base.weekday + 7) % 7;
    return base.add(Duration(days: delta));
  }
}

final class _TemporalTimeOfDay {
  const _TemporalTimeOfDay({
    required this.hour,
    required this.minute,
    required this.matchedText,
    required this.label,
  });

  final int hour;
  final int minute;
  final String matchedText;
  final String label;
}
