import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../core/ai/semantic_parse_edit_policy.dart';
import '../time/time_resolver.dart';
import 'todo_linking.dart';
import 'todo_thread_match.dart';

sealed class MessageActionDecision {
  const MessageActionDecision();
}

final class MessageActionNoneDecision extends MessageActionDecision {
  const MessageActionNoneDecision();
}

final class MessageActionFollowUpDecision extends MessageActionDecision {
  const MessageActionFollowUpDecision({
    required this.todoId,
    required this.newStatus,
  });

  final String todoId;
  final String newStatus; // "in_progress" | "done" | "dismissed"
}

final class MessageActionRecurrenceRule {
  const MessageActionRecurrenceRule({
    required this.freq,
    this.interval = 1,
  });

  final String freq; // daily | weekly | monthly | yearly
  final int interval;

  Map<String, Object> toJsonMap() => <String, Object>{
        'freq': freq,
        'interval': interval,
      };

  String toJsonString() => jsonEncode(toJsonMap());
}

final class MessageActionCreateDecision extends MessageActionDecision {
  const MessageActionCreateDecision({
    required this.title,
    required this.status,
    this.dueAtLocal,
    this.recurrenceRule,
  });

  final String title;
  final String status; // "open" | "inbox"
  final DateTime? dueAtLocal;
  final MessageActionRecurrenceRule? recurrenceRule;
}

class MessageActionResolver {
  static final RegExp _todoPrefix =
      RegExp(r'^\s*todo\s*[:：]\s*(.+)$', caseSensitive: false);
  static final RegExp _checkboxPrefix = RegExp(r'^\s*[-*]\s*\[\s*\]\s*(.+)$');
  static final RegExp _time24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final RegExp _timeAmPm =
      RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
  static final RegExp _timeZh = RegExp(
    r'(?:(?:上|下)午|早上|晚上|中午|凌晨)?\s*\d{1,2}\s*点(?:\s*(?:[0-5]?\d\s*分?|半))?',
  );

  static const List<({String freq, String token})> _recurrenceTokens = [
    (freq: 'daily', token: 'every day'),
    (freq: 'daily', token: 'daily'),
    (freq: 'daily', token: '每天'),
    (freq: 'daily', token: '每日'),
    (freq: 'daily', token: 'quotidien'),
    (freq: 'daily', token: '毎日'),
    (freq: 'daily', token: '매일'),
    (freq: 'daily', token: 'todos los dias'),
    (freq: 'daily', token: 'todos los días'),
    (freq: 'weekly', token: 'every week'),
    (freq: 'weekly', token: 'weekly'),
    (freq: 'weekly', token: '每周'),
    (freq: 'weekly', token: '每週'),
    (freq: 'weekly', token: '毎週'),
    (freq: 'weekly', token: '매주'),
    (freq: 'weekly', token: 'cada semana'),
    (freq: 'weekly', token: 'chaque semaine'),
    (freq: 'weekly', token: 'jede woche'),
    (freq: 'monthly', token: 'every month'),
    (freq: 'monthly', token: 'monthly'),
    (freq: 'monthly', token: '每月'),
    (freq: 'monthly', token: '毎月'),
    (freq: 'monthly', token: '매월'),
    (freq: 'monthly', token: 'cada mes'),
    (freq: 'monthly', token: 'chaque mois'),
    (freq: 'monthly', token: 'jeden monat'),
    (freq: 'yearly', token: 'every year'),
    (freq: 'yearly', token: 'yearly'),
    (freq: 'yearly', token: '每年'),
    (freq: 'yearly', token: '毎年'),
    (freq: 'yearly', token: '매년'),
    (freq: 'yearly', token: 'cada año'),
    (freq: 'yearly', token: 'cada ano'),
    (freq: 'yearly', token: 'chaque annee'),
    (freq: 'yearly', token: 'chaque année'),
    (freq: 'yearly', token: 'jedes jahr'),
  ];

  static String _normalizeForRecurrence(String text) {
    final lower = text.toLowerCase();
    final normalized = lower
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('å', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c');
    return normalized;
  }

  static MessageActionRecurrenceRule? _detectRecurrenceRule(String text) {
    final normalized = _normalizeForRecurrence(text);
    for (final entry in _recurrenceTokens) {
      final tokenNormalized = _normalizeForRecurrence(entry.token);
      if (normalized.contains(tokenNormalized)) {
        return MessageActionRecurrenceRule(freq: entry.freq, interval: 1);
      }
    }
    return null;
  }

  static String _stripRecurrenceDecorations(String text) {
    var out = text;
    final normalized = _normalizeForRecurrence(text);
    for (final entry in _recurrenceTokens) {
      final tokenNormalized = _normalizeForRecurrence(entry.token);
      if (!normalized.contains(tokenNormalized)) continue;
      out = out.replaceAll(
          RegExp(RegExp.escape(entry.token), caseSensitive: false), ' ');
      if (tokenNormalized != entry.token) {
        out = out.replaceAll(
            RegExp(RegExp.escape(tokenNormalized), caseSensitive: false), ' ');
      }
    }

    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[,，:：\-–—\s]+'), '').trim();
    out = out.replaceAll(
      RegExp(r'(?<=[\u4E00-\u9FFF])\s+(?=[\u4E00-\u9FFF])'),
      '',
    );
    return out;
  }

  static String _cleanupRecurringTitleArtifacts(String text) {
    var out = text;
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'([是为為])\s*[，,]\s*'), '');
    out = out.replaceAll(RegExp(r'\s*[，,]\s*'), ' ');
    out = out.replaceAll('的这个时候', ' ');
    out = out.replaceAll('這個時候', ' ');
    out = out.replaceAll('这个时候', ' ');
    out = out.replaceAll(RegExp(r'^\s*每(?:个)?\s*'), '');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[,，:：\-–—\s]+'), '').trim();
    out = out.replaceAll(
      RegExp(r'(?<=[\u4E00-\u9FFF])\s+(?=[\u4E00-\u9FFF])'),
      '',
    );
    return out;
  }

  static String? _extractStructuredTitle(String text) {
    final trimmed = text.trim();
    final todoMatch = _todoPrefix.firstMatch(trimmed);
    if (todoMatch != null) {
      final t = todoMatch.group(1)?.trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final boxMatch = _checkboxPrefix.firstMatch(trimmed);
    if (boxMatch != null) {
      final t = boxMatch.group(1)?.trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return null;
  }

  static int _semanticBoost(int rank, double distance) {
    if (!distance.isFinite) return 0;
    final base = distance <= 0.35
        ? 2200
        : distance <= 0.50
            ? 1400
            : distance <= 0.70
                ? 800
                : 0;
    if (base == 0) return 0;

    final factor = switch (rank) {
      0 => 1.0,
      1 => 0.7,
      2 => 0.5,
      3 => 0.4,
      _ => 0.3,
    };
    return (base * factor).round();
  }

  static int _dueBoost(DateTime? dueLocal, DateTime nowLocal) {
    if (dueLocal == null) return 0;
    final diffMinutes = dueLocal.difference(nowLocal).inMinutes.abs();
    if (diffMinutes <= 120) return 1500;
    if (diffMinutes <= 360) return 800;
    if (diffMinutes <= 1440) return 200;
    return 0;
  }

  static List<TodoLinkCandidate> _mergeSemanticMatches({
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required List<TodoThreadMatch> semanticMatches,
    required int limit,
  }) {
    final ranked =
        rankTodoCandidates(query, targets, nowLocal: nowLocal, limit: limit);
    if (ranked.isEmpty) return ranked;

    final targetsById = <String, TodoLinkTarget>{};
    for (final t in targets) {
      targetsById[t.id] = t;
    }

    final scoreByTodoId = <String, int>{};
    final queryLower = query.trim().toLowerCase();
    final queryCompact = queryLower.replaceAll(RegExp(r'\s+'), '');
    for (final c in ranked) {
      var score = c.score;
      final titleLower = c.target.title.trim().toLowerCase();
      final titleCompact = titleLower.replaceAll(RegExp(r'\s+'), '');
      if (titleCompact.runes.length >= 2 &&
          (queryLower.contains(titleLower) ||
              queryCompact.contains(titleCompact))) {
        score += 5000;
      }
      scoreByTodoId[c.target.id] = score;
    }

    for (var i = 0; i < semanticMatches.length && i < limit; i++) {
      final match = semanticMatches[i];
      final target = targetsById[match.todoId];
      if (target == null) continue;

      final boost = _semanticBoost(i, match.distance);
      if (boost <= 0) continue;

      final existing = scoreByTodoId[target.id];
      final base = existing ?? _dueBoost(target.dueLocal, nowLocal);
      scoreByTodoId[target.id] = base + boost;
    }

    final merged = <TodoLinkCandidate>[];
    scoreByTodoId.forEach((id, score) {
      final target = targetsById[id];
      if (target == null) return;
      merged.add(TodoLinkCandidate(target: target, score: score));
    });
    merged.sort((a, b) => b.score.compareTo(a.score));
    if (merged.length <= limit) return merged;
    return merged.sublist(0, limit);
  }

  static String _stripTimeDecorations(String text, LocalTimeResolution? time) {
    var out = text;

    final matched = time?.matchedText.trim();
    if (matched != null && matched.isNotEmpty) {
      out = out.replaceAll(
          RegExp(RegExp.escape(matched), caseSensitive: false), ' ');
    }

    out = out.replaceAll(_time24h, ' ');
    out = out.replaceAll(_timeAmPm, ' ');
    out = out.replaceAll(_timeZh, ' ');

    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[,，:：\-–—\s]+'), '').trim();
    return out;
  }

  static int _firstWeekdayFromIndex(int firstDayOfWeekIndex) {
    if (firstDayOfWeekIndex == 0) return DateTime.sunday;
    return firstDayOfWeekIndex.clamp(DateTime.monday, DateTime.saturday);
  }

  static DateTime _startOfWeek(DateTime nowLocal, int firstDayOfWeekIndex) {
    final firstWeekday = _firstWeekdayFromIndex(firstDayOfWeekIndex);
    final delta = (nowLocal.weekday - firstWeekday + 7) % 7;
    return DateTime(nowLocal.year, nowLocal.month, nowLocal.day)
        .subtract(Duration(days: delta));
  }

  static DateTime _nextRecurringCycleStart(
    DateTime cycleStart,
    MessageActionRecurrenceRule recurrenceRule,
  ) {
    switch (recurrenceRule.freq) {
      case 'weekly':
        return cycleStart.add(Duration(days: 7 * recurrenceRule.interval));
      case 'monthly':
        return DateTime(
          cycleStart.year,
          cycleStart.month + recurrenceRule.interval,
          1,
        );
      case 'yearly':
        return DateTime(cycleStart.year + recurrenceRule.interval, 1, 1);
      case 'daily':
      default:
        return cycleStart.add(Duration(days: recurrenceRule.interval));
    }
  }

  static DateTime _fallbackDueAtForRecurring(
    DateTime nowLocal,
    MessageActionRecurrenceRule recurrenceRule, {
    required int morningMinutes,
    required int firstDayOfWeekIndex,
  }) {
    final hour = morningMinutes ~/ 60;
    final minute = morningMinutes % 60;

    DateTime cycleStart;
    switch (recurrenceRule.freq) {
      case 'weekly':
        cycleStart = _startOfWeek(nowLocal, firstDayOfWeekIndex);
        break;
      case 'monthly':
        cycleStart = DateTime(nowLocal.year, nowLocal.month, 1);
        break;
      case 'yearly':
        cycleStart = DateTime(nowLocal.year, 1, 1);
        break;
      case 'daily':
      default:
        cycleStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        break;
    }

    var dueAtLocal = DateTime(
      cycleStart.year,
      cycleStart.month,
      cycleStart.day,
      hour,
      minute,
    );

    while (!dueAtLocal.isAfter(nowLocal)) {
      cycleStart = _nextRecurringCycleStart(cycleStart, recurrenceRule);
      dueAtLocal = DateTime(
        cycleStart.year,
        cycleStart.month,
        cycleStart.day,
        hour,
        minute,
      );
    }

    return dueAtLocal;
  }

  static MessageActionDecision resolve(
    String text, {
    required Locale locale,
    required DateTime nowLocal,
    required int dayEndMinutes,
    required List<TodoLinkTarget> openTodoTargets,
    int? morningMinutes,
    int firstDayOfWeekIndex = 1,
    List<TodoThreadMatch> semanticMatches = const <TodoThreadMatch>[],
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return const MessageActionNoneDecision();

    final resolvedMorningMinutes = morningMinutes ?? dayEndMinutes;
    final updateIntent = inferTodoUpdateIntent(raw);

    // Follow-up (existing todo)
    if (openTodoTargets.isNotEmpty) {
      final ranked = _mergeSemanticMatches(
        query: raw,
        targets: openTodoTargets,
        nowLocal: nowLocal,
        semanticMatches: semanticMatches,
        limit: 5,
      );

      if (ranked.isNotEmpty) {
        final top = ranked[0];
        final secondScore = ranked.length > 1 ? ranked[1].score : 0;
        final highConfidence = top.score >= 3200 ||
            (top.score >= 2400 && (top.score - secondScore) >= 900) ||
            (updateIntent.isExplicit &&
                top.score >= 1600 &&
                (top.score - secondScore) >= 500);

        if (highConfidence) {
          return MessageActionFollowUpDecision(
            todoId: top.target.id,
            newStatus: updateIntent.newStatus,
          );
        }
      }
    }

    if (isLongTextForTodoAutomation(raw)) {
      return const MessageActionNoneDecision();
    }

    // Create (new todo)
    final recurrenceRule = _detectRecurrenceRule(raw);
    final time = LocalTimeResolver.resolve(
      raw,
      nowLocal,
      locale: locale,
      dayEndMinutes: dayEndMinutes,
    );

    final structuredTitle = _extractStructuredTitle(raw);
    if (structuredTitle != null) {
      final dueAtLocal = time?.candidates.length == 1
          ? time!.candidates.single.dueAtLocal
          : recurrenceRule == null
              ? null
              : _fallbackDueAtForRecurring(
                  nowLocal,
                  recurrenceRule,
                  morningMinutes: resolvedMorningMinutes,
                  firstDayOfWeekIndex: firstDayOfWeekIndex,
                );
      var title = _stripRecurrenceDecorations(structuredTitle);
      if (recurrenceRule != null) {
        title = _cleanupRecurringTitleArtifacts(title);
      }
      return MessageActionCreateDecision(
        title: title,
        status: dueAtLocal == null ? 'inbox' : 'open',
        dueAtLocal: dueAtLocal,
        recurrenceRule: recurrenceRule,
      );
    }

    final isDoneOrDismiss = updateIntent.isExplicit &&
        (updateIntent.newStatus == 'done' ||
            updateIntent.newStatus == 'dismissed');
    if (isDoneOrDismiss) {
      return const MessageActionNoneDecision();
    }

    if (time == null && recurrenceRule == null) {
      return const MessageActionNoneDecision();
    }

    final dueAtLocal = time != null && time.candidates.length == 1
        ? time.candidates.single.dueAtLocal
        : recurrenceRule == null
            ? null
            : _fallbackDueAtForRecurring(
                nowLocal,
                recurrenceRule,
                morningMinutes: resolvedMorningMinutes,
                firstDayOfWeekIndex: firstDayOfWeekIndex,
              );
    if (time != null && time.candidates.length != 1 && recurrenceRule == null) {
      return const MessageActionNoneDecision();
    }

    var title = _stripTimeDecorations(raw, time);
    title = _stripRecurrenceDecorations(title);
    if (recurrenceRule != null) {
      title = _cleanupRecurringTitleArtifacts(title);
    }
    if (title.isEmpty) return const MessageActionNoneDecision();

    return MessageActionCreateDecision(
      title: title,
      status: dueAtLocal == null ? 'inbox' : 'open',
      dueAtLocal: dueAtLocal,
      recurrenceRule: recurrenceRule,
    );
  }
}
