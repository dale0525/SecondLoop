import 'package:flutter/widgets.dart';

import '../actions/time/time_range_resolver.dart';

enum AskAiIntentKind {
  none,
  past,
  future,
  both,
}

class AskAiIntent {
  const AskAiIntent({
    required this.kind,
    required this.confidence,
    this.timeRange,
  });

  final AskAiIntentKind kind;
  final double confidence;
  final LocalTimeRangeResolution? timeRange;
}

class AskAiIntentResolver {
  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (n.isEmpty) continue;
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  static AskAiIntent resolve(
    String question,
    DateTime nowLocal, {
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) {
    final raw = question.trim();
    if (raw.isEmpty) {
      return const AskAiIntent(kind: AskAiIntentKind.none, confidence: 0);
    }

    final norm = _normalize(raw);
    final timeRange = LocalTimeRangeResolver.resolve(
      raw,
      nowLocal,
      locale: locale,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );

    final pastTokens = <String>[
      // en
      'what did i',
      'did i',
      'yesterday',
      // zh
      '做了什么',
      '干了什么',
      '做了',
      '干了',
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

    final futureTokens = <String>[
      // en
      'what should i do',
      'should i',
      'need to',
      'tomorrow',
      // zh
      '要做',
      '要干',
      '需要',
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

    final isPast = _containsAny(norm, pastTokens) ||
        _containsAny(raw, const <String>['上周', '上週']) ||
        _containsAny(raw, const <String>['昨天', '昨日', '어제']);
    final isFuture = _containsAny(norm, futureTokens) ||
        _containsAny(raw, const <String>['明天', '明日', '내일']);

    final kind = switch ((isPast, isFuture)) {
      (true, true) => AskAiIntentKind.both,
      (true, false) => AskAiIntentKind.past,
      (false, true) => AskAiIntentKind.future,
      _ => AskAiIntentKind.none,
    };

    final confidence = switch (kind) {
      AskAiIntentKind.none => timeRange == null ? 0.0 : 0.55,
      _ => 0.9,
    };

    return AskAiIntent(
        kind: kind, confidence: confidence, timeRange: timeRange);
  }
}
