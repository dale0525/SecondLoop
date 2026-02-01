import 'package:flutter/widgets.dart';

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
  static final List<String> _tomorrowTokens = <String>[
    // en
    'tomorrow',
    // zh
    '明天',
    // ja
    '明日',
    // ko
    '내일',
    // es
    'mañana',
    // fr
    'demain',
    // de
    'morgen',
  ];

  static final List<String> _yesterdayTokens = <String>[
    // en
    'yesterday',
    // zh
    '昨天',
    // ja
    '昨日',
    // ko
    '어제',
    // es
    'ayer',
    // fr
    'hier',
    // de
    'gestern',
  ];

  static final List<String> _lastWeekTokens = <String>[
    // en
    'last week',
    // zh
    '上周',
    '上週',
    '上星期',
    '上週期',
    // ja
    '先週',
    // ko
    '지난주',
    // es
    'la semana pasada',
    // fr
    'la semaine dernière',
    // de
    'letzte woche',
  ];

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (n.isEmpty) continue;
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  static DateTime _startOfDay(DateTime local) =>
      DateTime(local.year, local.month, local.day);

  static int _firstWeekdayFromIndex(int firstDayOfWeekIndex) {
    // `MaterialLocalizations.firstDayOfWeekIndex` uses 0..6 (Sun..Sat).
    // `DateTime.weekday` uses 1..7 (Mon..Sun).
    if (firstDayOfWeekIndex == 0) return DateTime.sunday;
    return firstDayOfWeekIndex.clamp(DateTime.monday, DateTime.saturday);
  }

  static DateTime _startOfWeek(DateTime nowLocal, int firstDayOfWeekIndex) {
    final firstWeekday = _firstWeekdayFromIndex(firstDayOfWeekIndex);
    final diff = (nowLocal.weekday - firstWeekday + 7) % 7;
    final start = nowLocal.subtract(Duration(days: diff));
    return _startOfDay(start);
  }

  static LocalTimeRangeResolution? resolve(
    String text,
    DateTime nowLocal, {
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return null;

    final norm = _normalize(raw);

    if (_containsAny(norm, _tomorrowTokens) ||
        _containsAny(raw, const <String>['明天', '明日', '내일'])) {
      final start = _startOfDay(nowLocal.add(const Duration(days: 1)));
      final end = start.add(const Duration(days: 1));
      return LocalTimeRangeResolution(
        kind: 'tomorrow',
        matchedText: raw,
        startLocal: start,
        endLocal: end,
      );
    }

    if (_containsAny(norm, _yesterdayTokens) ||
        _containsAny(raw, const <String>['昨天', '昨日', '어제'])) {
      final start = _startOfDay(nowLocal.subtract(const Duration(days: 1)));
      final end = _startOfDay(nowLocal);
      return LocalTimeRangeResolution(
        kind: 'yesterday',
        matchedText: raw,
        startLocal: start,
        endLocal: end,
      );
    }

    if (_containsAny(norm, _lastWeekTokens) ||
        _containsAny(raw, const <String>['上周', '上週'])) {
      final thisWeekStart = _startOfWeek(nowLocal, firstDayOfWeekIndex);
      final start = thisWeekStart.subtract(const Duration(days: 7));
      final end = thisWeekStart;
      return LocalTimeRangeResolution(
        kind: 'last_week',
        matchedText: raw,
        startLocal: start,
        endLocal: end,
      );
    }

    return null;
  }
}
