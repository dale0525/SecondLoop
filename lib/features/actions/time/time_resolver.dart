import 'package:flutter/widgets.dart';

class DueCandidate {
  const DueCandidate({
    required this.dueAtLocal,
    required this.label,
  });

  final DateTime dueAtLocal;
  final String label;
}

class LocalTimeResolution {
  const LocalTimeResolution({
    required this.kind,
    required this.matchedText,
    required this.candidates,
  });

  final String kind;
  final String matchedText;
  final List<DueCandidate> candidates;
}

class LocalTimeResolver {
  static final RegExp _isoDate = RegExp(
    r'\b(\d{4})\s*[-‐‑–—−－]\s*(\d{1,2})\s*[-‐‑–—−－]\s*(\d{1,2})\b',
  );
  static final RegExp _slashDate =
      RegExp(r'\b(\d{1,2})\s*[\/／]\s*(\d{1,2})(?:\s*[\/／]\s*(\d{2,4}))?\b');
  static final RegExp _cjkMonthDay = RegExp(
    r'(?<!\d)(\d{1,2})\s*(?:月|월)\s*(\d{1,2})\s*(?:日|号|號|일)(?!\d)',
  );
  static final RegExp _time24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final RegExp _timeAmPm =
      RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
  static final RegExp _zhMeridiemTime = RegExp(
    r'(上午|早上|凌晨|中午|下午|晚上|今晚|今夜|夜里|夜晚)\s*(\d{1,2})(?:[:：](\d{2}))?\s*(?:点|點|时|時)(?:\s*(半))?',
  );

  static final List<MapEntry<String, int>> _relativeDayTokens = [
    // day after tomorrow (2)
    const MapEntry('day after tomorrow', 2),
    const MapEntry('after tomorrow', 2),
    const MapEntry('pasado mañana', 2),
    const MapEntry('après-demain', 2),
    const MapEntry('übermorgen', 2),
    const MapEntry('明後日', 2),
    const MapEntry('모레', 2),
    // 3 days later (3)
    const MapEntry('大后天', 3),
    const MapEntry('大後天', 3),
    // tomorrow morning / tomorrow (1)
    const MapEntry('tomorrow morning', 1),
    const MapEntry('mañana por la mañana', 1),
    const MapEntry('demain matin', 1),
    const MapEntry('morgen früh', 1),
    const MapEntry('明日の朝', 1),
    const MapEntry('내일 아침', 1),
    const MapEntry('明早', 1),
    const MapEntry('明晨', 1),
    const MapEntry('tomorrow', 1),
    const MapEntry('mañana', 1),
    const MapEntry('demain', 1),
    const MapEntry('morgen', 1),
    const MapEntry('明日', 1),
    const MapEntry('내일', 1),
    const MapEntry('明天', 1),
    // today / tonight (0)
    const MapEntry("aujourd'hui", 0),
    const MapEntry('heute abend', 0),
    const MapEntry('heute', 0),
    const MapEntry('ce soir', 0),
    const MapEntry('esta noche', 0),
    const MapEntry('tonight', 0),
    const MapEntry('today', 0),
    const MapEntry('今日', 0),
    const MapEntry('今日の夜', 0),
    const MapEntry('今夜', 0),
    const MapEntry('오늘', 0),
    const MapEntry('오늘 밤', 0),
    const MapEntry('今天', 0),
    const MapEntry('今晚', 0),
    // zh: after tomorrow (2) - keep at the end to avoid matching "后天" inside "大后天"
    const MapEntry('后天', 2),
    const MapEntry('後天', 2),
  ];

  static final List<({int weekday, Set<String> tokens})> _weekdayTokens = [
    (
      weekday: DateTime.monday,
      tokens: {
        // zh
        '周一',
        '週一',
        '星期一',
        '礼拜一',
        '禮拜一',
        // en
        'monday',
        // ja
        '月曜',
        '月曜日',
        // ko
        '월요일',
        // es
        'lunes',
        // fr
        'lundi',
        // de
        'montag',
      },
    ),
    (
      weekday: DateTime.tuesday,
      tokens: {
        // zh
        '周二',
        '週二',
        '星期二',
        '礼拜二',
        '禮拜二',
        // en
        'tuesday',
        // ja
        '火曜',
        '火曜日',
        // ko
        '화요일',
        // es
        'martes',
        // fr
        'mardi',
        // de
        'dienstag',
      },
    ),
    (
      weekday: DateTime.wednesday,
      tokens: {
        // zh
        '周三',
        '週三',
        '星期三',
        '礼拜三',
        '禮拜三',
        // en
        'wednesday',
        // ja
        '水曜',
        '水曜日',
        // ko
        '수요일',
        // es
        'miércoles',
        'miercoles',
        // fr
        'mercredi',
        // de
        'mittwoch',
      },
    ),
    (
      weekday: DateTime.thursday,
      tokens: {
        // zh
        '周四',
        '週四',
        '星期四',
        '礼拜四',
        '禮拜四',
        // en
        'thursday',
        // ja
        '木曜',
        '木曜日',
        // ko
        '목요일',
        // es
        'jueves',
        // fr
        'jeudi',
        // de
        'donnerstag',
      },
    ),
    (
      weekday: DateTime.friday,
      tokens: {
        // zh
        '周五',
        '週五',
        '星期五',
        '礼拜五',
        '禮拜五',
        // en
        'friday',
        // ja
        '金曜',
        '金曜日',
        // ko
        '금요일',
        // es
        'viernes',
        // fr
        'vendredi',
        // de
        'freitag',
      },
    ),
    (
      weekday: DateTime.saturday,
      tokens: {
        // zh
        '周六',
        '週六',
        '星期六',
        '礼拜六',
        '禮拜六',
        // en
        'saturday',
        // ja
        '土曜',
        '土曜日',
        // ko
        '토요일',
        // es
        'sábado',
        'sabado',
        // fr
        'samedi',
        // de
        'samstag',
        'sonnabend',
      },
    ),
    (
      weekday: DateTime.sunday,
      tokens: {
        // zh
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
        // en
        'sunday',
        // ja
        '日曜',
        '日曜日',
        // ko
        '일요일',
        // es
        'domingo',
        // fr
        'dimanche',
        // de
        'sonntag',
      },
    ),
  ];

  static final Set<String> _weekendTokens = {
    // zh
    '周末',
    '週末',
    '这周末',
    '本周末',
    '下周末',
    '这个周末',
    // en
    'weekend',
    'this weekend',
    'next weekend',
    // ja
    '今週末',
    '来週末',
    // ko
    '주말',
    '이번 주말',
    '다음 주말',
    // es
    'fin de semana',
    'este fin de semana',
    'próximo fin de semana',
    // fr
    'week-end',
    'ce week-end',
    'week-end prochain',
    // de
    'wochenende',
    'dieses wochenende',
    'nächstes wochenende',
  };

  static final Set<String> _monthEndTokens = {
    // zh
    '月底',
    '月末',
    '本月底',
    '下月底',
    '月的终了',
    // en
    'end of month',
    'eom',
    // ja
    '月の終わり',
    // ko
    '월말',
    // es
    'fin de mes',
    // fr
    'fin du mois',
    // de
    'monatsende',
  };

  static final Set<String> _monthStartTokens = {
    // zh
    '月初',
    '本月初',
    '下月初',
    // en
    'start of month',
    'beginning of month',
    // ja
    '月の初め',
    // ko
    '월초',
    // es
    'principio de mes',
    // fr
    'début du mois',
    // de
    'monatsanfang',
  };

  static final Set<String> _yearEndTokens = {
    // zh
    '年底',
    '年末',
    '今年底',
    '明年底',
    // en
    'end of year',
    'eoy',
    // ja
    '今年末',
    '来年末',
    // ko
    '연말',
    '올해 말',
    '내년 말',
    // es
    'fin de año',
    // fr
    "fin de l'année",
    // de
    'jahresende',
  };

  static final Map<String, ({int month, int day})> _fixedHolidays = {
    // Christmas
    'christmas': (month: 12, day: 25),
    '圣诞节': (month: 12, day: 25),
    'クリスマス': (month: 12, day: 25),
    '크리스마스': (month: 12, day: 25),
    'navidad': (month: 12, day: 25),
    'noël': (month: 12, day: 25),
    'weihnachten': (month: 12, day: 25),
    // New Year
    "new year's day": (month: 1, day: 1),
    '元旦': (month: 1, day: 1),
    'お正月': (month: 1, day: 1),
    '새해': (month: 1, day: 1),
    'año nuevo': (month: 1, day: 1),
    'nouvel an': (month: 1, day: 1),
    'neujahr': (month: 1, day: 1),
    // Valentine
    "valentine's day": (month: 2, day: 14),
    '情人节': (month: 2, day: 14),
    'バレンタイン': (month: 2, day: 14),
    '발렌타인데이': (month: 2, day: 14),
    'san valentín': (month: 2, day: 14),
    'saint-valentin': (month: 2, day: 14),
    'valentinstag': (month: 2, day: 14),
    // Halloween
    'halloween': (month: 10, day: 31),
    '万圣节': (month: 10, day: 31),
    'ハロウィン': (month: 10, day: 31),
    '할로윈': (month: 10, day: 31),
  };

  static final Set<String> _reviewIntentTokens = {
    // zh
    '记得',
    '别忘',
    '不要忘',
    '提醒我',
    // en
    'remember',
    "don't forget",
    'remind me',
    // ja
    '覚えて',
    '忘れないで',
    'リマインド',
    // ko
    '기억해',
    '잊지마',
    '알림',
    // es
    'recuérdame',
    'no lo olvides',
    // fr
    'rappelle-moi',
    "n'oublie pas",
    // de
    'erinnere mich',
    'vergiss nicht',
  };

  static LocalTimeResolution? resolve(
    String text,
    DateTime nowLocal, {
    required Locale locale,
    required int dayEndMinutes,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;

    final lower = normalized.toLowerCase();
    final dayEnd = _atDayEnd(nowLocal, dayEndMinutes);
    final timeOfDay = _parseTimeOfDay(normalized, lower);

    // 1) Explicit ISO date: 2026-01-31
    final isoMatch = _isoDate.firstMatch(normalized);
    if (isoMatch != null) {
      final year = int.tryParse(isoMatch.group(1)!);
      final month = int.tryParse(isoMatch.group(2)!);
      final day = int.tryParse(isoMatch.group(3)!);
      if (year != null &&
          month != null &&
          day != null &&
          _isValidDate(year, month, day)) {
        final due = timeOfDay == null
            ? DateTime(year, month, day, dayEnd.hour, dayEnd.minute)
            : DateTime(year, month, day, timeOfDay.hour, timeOfDay.minute);
        return LocalTimeResolution(
          kind: 'date',
          matchedText: isoMatch.group(0)!,
          candidates: [
            DueCandidate(
              dueAtLocal: due,
              label: timeOfDay == null
                  ? _formatDateLabel(due, locale)
                  : _formatDateTimeLabel(due, locale),
            ),
          ],
        );
      }
    }

    // 2) Slash date: 1/31 or 1/31/2026
    final slashMatch = _slashDate.firstMatch(normalized);
    if (slashMatch != null) {
      final month = int.tryParse(slashMatch.group(1)!);
      final day = int.tryParse(slashMatch.group(2)!);
      final yearRaw = slashMatch.group(3);
      if (month != null && day != null) {
        final year = yearRaw == null
            ? null
            : (yearRaw.length == 2
                ? 2000 + int.parse(yearRaw)
                : int.parse(yearRaw));
        final resolvedYear =
            year ?? _resolveYearForMonthDay(nowLocal, month, day);
        if (_isValidDate(resolvedYear, month, day)) {
          final due = timeOfDay == null
              ? DateTime(
                  resolvedYear,
                  month,
                  day,
                  dayEnd.hour,
                  dayEnd.minute,
                )
              : DateTime(
                  resolvedYear,
                  month,
                  day,
                  timeOfDay.hour,
                  timeOfDay.minute,
                );
          return LocalTimeResolution(
            kind: 'date',
            matchedText: slashMatch.group(0)!,
            candidates: [
              DueCandidate(
                dueAtLocal: due,
                label: timeOfDay == null
                    ? _formatDateLabel(due, locale)
                    : _formatDateTimeLabel(due, locale),
              ),
            ],
          );
        }
      }
    }

    // 3) CJK month/day: 3月1号 / 3 月 1 号 / 3월 1일
    final cjkMatch = _cjkMonthDay.firstMatch(normalized);
    if (cjkMatch != null) {
      final month = int.tryParse(cjkMatch.group(1)!);
      final day = int.tryParse(cjkMatch.group(2)!);
      if (month != null && day != null) {
        final year = _resolveYearForMonthDay(nowLocal, month, day);
        if (_isValidDate(year, month, day)) {
          final due = timeOfDay == null
              ? DateTime(year, month, day, dayEnd.hour, dayEnd.minute)
              : DateTime(year, month, day, timeOfDay.hour, timeOfDay.minute);
          return LocalTimeResolution(
            kind: 'date',
            matchedText: cjkMatch.group(0)!,
            candidates: [
              DueCandidate(
                dueAtLocal: due,
                label: timeOfDay == null
                    ? _formatDateLabel(due, locale)
                    : _formatDateTimeLabel(due, locale),
              ),
            ],
          );
        }
      }
    }

    // 3) Relative day anchors
    final relative = _matchRelativeDayToken(normalized, lower);
    if (relative != null) {
      final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      final day = base.add(Duration(days: relative.value));
      final due = timeOfDay == null
          ? _atDayEnd(day, dayEndMinutes)
          : DateTime(
              day.year, day.month, day.day, timeOfDay.hour, timeOfDay.minute);
      return LocalTimeResolution(
        kind: 'relative_day',
        matchedText: relative.key,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatDateLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    // 4) Weekday anchor (Mon..Sun)
    final weekdayMatch = _matchWeekdayToken(normalized, lower);
    if (weekdayMatch != null) {
      final next = _nextWeekdayOnOrAfter(nowLocal, weekdayMatch.weekday);
      var due = timeOfDay == null
          ? _atDayEnd(next, dayEndMinutes)
          : DateTime(next.year, next.month, next.day, timeOfDay.hour,
              timeOfDay.minute);
      if (due.isBefore(nowLocal)) {
        due = due.add(const Duration(days: 7));
      }
      return LocalTimeResolution(
        kind: 'weekday',
        matchedText: weekdayMatch.token,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatWeekdayLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    // 5) Weekend anchor
    final weekendToken = _matchToken(normalized, lower, _weekendTokens);
    if (weekendToken != null) {
      final sat = _nextWeekdayOnOrAfter(nowLocal, DateTime.saturday);
      final sun = _nextWeekdayOnOrAfter(nowLocal, DateTime.sunday);
      final candidates = <DueCandidate>[
        DueCandidate(
          dueAtLocal: timeOfDay == null
              ? _atDayEnd(sat, dayEndMinutes)
              : DateTime(sat.year, sat.month, sat.day, timeOfDay.hour,
                  timeOfDay.minute),
          label: timeOfDay == null
              ? _formatWeekdayLabel(sat, locale)
              : _formatDateTimeLabel(
                  DateTime(sat.year, sat.month, sat.day, timeOfDay.hour,
                      timeOfDay.minute),
                  locale,
                ),
        ),
        DueCandidate(
          dueAtLocal: timeOfDay == null
              ? _atDayEnd(sun, dayEndMinutes)
              : DateTime(sun.year, sun.month, sun.day, timeOfDay.hour,
                  timeOfDay.minute),
          label: timeOfDay == null
              ? _formatWeekdayLabel(sun, locale)
              : _formatDateTimeLabel(
                  DateTime(sun.year, sun.month, sun.day, timeOfDay.hour,
                      timeOfDay.minute),
                  locale,
                ),
        ),
      ];
      return LocalTimeResolution(
          kind: 'weekend', matchedText: weekendToken, candidates: candidates);
    }

    // 5) Month start/end anchors
    final monthStartToken = _matchToken(normalized, lower, _monthStartTokens);
    if (monthStartToken != null) {
      final candidateDay = DateTime(nowLocal.year, nowLocal.month, 1);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      final due = timeOfDay == null
          ? _atDayEnd(resolved, dayEndMinutes)
          : DateTime(resolved.year, resolved.month, resolved.day,
              timeOfDay.hour, timeOfDay.minute);
      return LocalTimeResolution(
        kind: 'month_start',
        matchedText: monthStartToken,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatDateLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    final monthEndToken = _matchToken(normalized, lower, _monthEndTokens);
    if (monthEndToken != null) {
      final lastDay = _lastDayOfMonth(nowLocal.year, nowLocal.month);
      final resolved = _nextOccurrence(lastDay, nowLocal);
      final due = timeOfDay == null
          ? _atDayEnd(resolved, dayEndMinutes)
          : DateTime(resolved.year, resolved.month, resolved.day,
              timeOfDay.hour, timeOfDay.minute);
      return LocalTimeResolution(
        kind: 'month_end',
        matchedText: monthEndToken,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatDateLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    // 6) Year end
    final yearEndToken = _matchToken(normalized, lower, _yearEndTokens);
    if (yearEndToken != null) {
      final candidateDay = DateTime(nowLocal.year, 12, 31);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      final due = timeOfDay == null
          ? _atDayEnd(resolved, dayEndMinutes)
          : DateTime(resolved.year, resolved.month, resolved.day,
              timeOfDay.hour, timeOfDay.minute);
      return LocalTimeResolution(
        kind: 'year_end',
        matchedText: yearEndToken,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatDateLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    // 7) Fixed holidays (multi-language tokens mapped to month/day)
    for (final entry in _fixedHolidays.entries) {
      final key = entry.key.toLowerCase();
      if (!lower.contains(key)) continue;
      final md = entry.value;
      final candidateDay = DateTime(nowLocal.year, md.month, md.day);
      final resolved = _nextOccurrence(candidateDay, nowLocal);
      final due = timeOfDay == null
          ? _atDayEnd(resolved, dayEndMinutes)
          : DateTime(resolved.year, resolved.month, resolved.day,
              timeOfDay.hour, timeOfDay.minute);
      return LocalTimeResolution(
        kind: 'holiday',
        matchedText: entry.key,
        candidates: [
          DueCandidate(
            dueAtLocal: due,
            label: timeOfDay == null
                ? _formatDateLabel(due, locale)
                : _formatDateTimeLabel(due, locale),
          ),
        ],
      );
    }

    // 8) Time-only (e.g. 15:30 or 3pm) - propose candidates for confirmation.
    if (timeOfDay != null) {
      final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      var first = DateTime(
        base.year,
        base.month,
        base.day,
        timeOfDay.hour,
        timeOfDay.minute,
      );
      if (first.isBefore(nowLocal)) {
        first = first.add(const Duration(days: 1));
      }
      final second = first.add(const Duration(days: 1));
      return LocalTimeResolution(
        kind: 'time_only',
        matchedText: timeOfDay.matchedText,
        candidates: [
          DueCandidate(
            dueAtLocal: first,
            label: _formatDateTimeLabel(first, locale),
          ),
          DueCandidate(
            dueAtLocal: second,
            label: _formatDateTimeLabel(second, locale),
          ),
        ],
      );
    }

    return null;
  }

  static bool looksLikeReviewIntent(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    final lower = normalized.toLowerCase();
    for (final token in _reviewIntentTokens) {
      final tokenLower = token.toLowerCase();
      if (tokenLower.contains(' ')) {
        if (lower.contains(tokenLower)) return true;
        continue;
      }
      if (lower.contains(tokenLower)) return true;
      if (normalized.contains(token)) return true;
    }
    return false;
  }

  static String? _matchToken(
      String original, String lower, Set<String> tokens) {
    for (final token in tokens) {
      final tokenLower = token.toLowerCase();
      if (tokenLower.contains(' ')) {
        if (lower.contains(tokenLower)) return token;
        continue;
      }
      if (lower.contains(tokenLower)) return token;
      if (original.contains(token)) return token;
    }
    return null;
  }

  static MapEntry<String, int>? _matchRelativeDayToken(
      String original, String lower) {
    for (final entry in _relativeDayTokens) {
      final token = entry.key;
      final tokenLower = token.toLowerCase();
      if (tokenLower.contains(' ')) {
        if (lower.contains(tokenLower)) return entry;
        continue;
      }
      if (lower.contains(tokenLower)) return entry;
      if (original.contains(token)) return entry;
    }
    return null;
  }

  static ({String token, int weekday})? _matchWeekdayToken(
      String original, String lower) {
    for (final entry in _weekdayTokens) {
      final token = _matchToken(original, lower, entry.tokens);
      if (token == null) continue;
      return (token: token, weekday: entry.weekday);
    }
    return null;
  }

  static ({int hour, int minute, String matchedText})? _parseTimeOfDay(
    String original,
    String lower,
  ) {
    final match24 = _time24h.firstMatch(original);
    if (match24 != null) {
      final hour = int.tryParse(match24.group(1) ?? '');
      final minute = int.tryParse(match24.group(2) ?? '');
      if (hour != null && minute != null) {
        return (hour: hour, minute: minute, matchedText: match24.group(0)!);
      }
    }

    final matchAmPm = _timeAmPm.firstMatch(original);
    if (matchAmPm != null) {
      var hour = int.tryParse(matchAmPm.group(1) ?? '');
      final minute = int.tryParse(matchAmPm.group(2) ?? '') ?? 0;
      final ampm = (matchAmPm.group(3) ?? '').toLowerCase();
      if (hour != null) {
        if (ampm == 'pm' && hour < 12) {
          hour += 12;
        } else if (ampm == 'am' && hour == 12) {
          hour = 0;
        }
        return (hour: hour, minute: minute, matchedText: matchAmPm.group(0)!);
      }
    }

    final zhMatch = _zhMeridiemTime.firstMatch(original);
    if (zhMatch != null) {
      final meridiem = zhMatch.group(1) ?? '';
      var hour = int.tryParse(zhMatch.group(2) ?? '');
      var minute = int.tryParse(zhMatch.group(3) ?? '') ?? 0;
      final half = zhMatch.group(4);
      if (half != null && half.trim().isNotEmpty) {
        minute = 30;
      }
      if (hour == null) return null;

      final isPm = switch (meridiem) {
        '下午' || '晚上' || '今晚' || '今夜' || '夜里' || '夜晚' => true,
        _ => false,
      };
      final isNoon = meridiem == '中午';
      final isEarly = meridiem == '凌晨';

      if (isNoon && hour < 12) {
        hour += 12;
      } else if (isPm && hour < 12) {
        hour += 12;
      } else if (isEarly && hour == 12) {
        hour = 0;
      }

      return (hour: hour, minute: minute, matchedText: zhMatch.group(0)!);
    }

    return null;
  }

  static bool _isValidDate(int year, int month, int day) {
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    final dt = DateTime(year, month, day);
    return dt.year == year && dt.month == month && dt.day == day;
  }

  static int _resolveYearForMonthDay(DateTime nowLocal, int month, int day) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final candidate = DateTime(nowLocal.year, month, day);
    if (candidate.isBefore(today)) return nowLocal.year + 1;
    return nowLocal.year;
  }

  static DateTime _nextWeekdayOnOrAfter(DateTime nowLocal, int weekday) {
    final base = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final deltaDays = (weekday - base.weekday) % 7;
    return base.add(Duration(days: deltaDays));
  }

  static DateTime _lastDayOfMonth(int year, int month) {
    final nextMonth =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1));
  }

  static DateTime _nextOccurrence(DateTime candidateDay, DateTime nowLocal) {
    final candidate =
        DateTime(candidateDay.year, candidateDay.month, candidateDay.day);
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (candidate.isBefore(today)) {
      if (candidate.month == 12 &&
          candidate.day == 31 &&
          candidate.year == today.year) {
        return DateTime(today.year + 1, 12, 31);
      }
      if (candidate.day == 1) {
        final nextMonth = today.month == 12
            ? DateTime(today.year + 1, 1, 1)
            : DateTime(today.year, today.month + 1, 1);
        return nextMonth;
      }
      if (candidate.month == today.month && candidate.year == today.year) {
        final nextMonth = today.month == 12
            ? DateTime(today.year + 1, 1, 1)
            : DateTime(today.year, today.month + 1, 1);
        return _lastDayOfMonth(nextMonth.year, nextMonth.month);
      }
      return DateTime(today.year + 1, candidate.month, candidate.day);
    }
    return candidate;
  }

  static DateTime _atDayEnd(DateTime dayLocal, int dayEndMinutes) {
    final hour = dayEndMinutes ~/ 60;
    final minute = dayEndMinutes % 60;
    return DateTime(dayLocal.year, dayLocal.month, dayLocal.day, hour, minute);
  }

  static String _formatDateLabel(DateTime dt, Locale locale) {
    // Keep it deterministic without pulling in intl for tests.
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _formatDateTimeLabel(DateTime dt, Locale locale) {
    // Keep it deterministic without pulling in intl for tests.
    final date = _formatDateLabel(dt, locale);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }

  static String _formatWeekdayLabel(DateTime dt, Locale locale) {
    // Simplified labels; UI can reformat later.
    return _formatDateLabel(dt, locale);
  }
}
