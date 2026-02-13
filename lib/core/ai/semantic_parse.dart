import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../features/actions/todo/message_action_resolver.dart';

class AiSemanticDecision {
  const AiSemanticDecision({required this.decision, required this.confidence});

  final MessageActionDecision decision;
  final double confidence;
}

class AiSemanticTimeWindow {
  const AiSemanticTimeWindow({
    required this.kind,
    required this.confidence,
    required this.startLocal,
    required this.endLocal,
  });

  final String kind; // none | past | future | both
  final double confidence;
  final DateTime startLocal;
  final DateTime endLocal;
}

class AiSemanticParse {
  static String? _extractFirstJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == r'\') {
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') depth++;
      if (ch != '}') continue;
      depth--;
      if (depth == 0) {
        return raw.substring(start, i + 1);
      }
    }
    return null;
  }

  static String? _stringField(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) return value.trim();
    return null;
  }

  static double? _doubleField(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static String _normalizeFullWidthDigits(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFF10 + 0x30);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static int? _intField(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = _normalizeFullWidthDigits(value.trim());
      return int.tryParse(normalized);
    }
    return null;
  }

  static String _normalizeRecurrenceText(String text) {
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
        .replaceAll('ç', 'c')
        .replaceAll('ß', 'ss');

    return normalized
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _compactRecurrenceText(String text) {
    return text.replaceAll(RegExp(r'[\s_\-.]+'), '');
  }

  static bool _matchesNormalizedAlias(
    String raw,
    String normalized,
    String compact,
    Set<String> latinAliases,
    Set<String> nonLatinAliases,
  ) {
    final rawCompact = _compactRecurrenceText(raw);

    for (final alias in latinAliases) {
      final aliasNormalized = _normalizeRecurrenceText(alias);
      final aliasCompact = _compactRecurrenceText(aliasNormalized);
      if (normalized == aliasNormalized || compact == aliasCompact) {
        return true;
      }
    }

    for (final alias in nonLatinAliases) {
      final aliasCompact = _compactRecurrenceText(alias);
      if (raw == alias || rawCompact == aliasCompact) {
        return true;
      }
    }

    return false;
  }

  static String? _canonicalRecurrenceFreq(String rawFreq) {
    final raw = rawFreq.trim();
    if (raw.isEmpty) return null;

    final normalized = _normalizeRecurrenceText(raw);
    final compact = _compactRecurrenceText(normalized);

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'daily',
        'every day',
        'everyday',
        'each day',
        'per day',
        'quotidien',
        'diario',
        'taglich',
      },
      const {'每天', '每日', '毎日', '매일'},
    )) {
      return 'daily';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'weekly',
        'every week',
        'each week',
        'per week',
        'hebdomadaire',
        'cada semana',
        'wochentlich',
      },
      const {'每周', '每週', '毎週', '매주'},
    )) {
      return 'weekly';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'monthly',
        'every month',
        'each month',
        'per month',
        'mensuel',
        'cada mes',
        'monatlich',
      },
      const {'每月', '毎月', '매월'},
    )) {
      return 'monthly';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'yearly',
        'annual',
        'annually',
        'every year',
        'each year',
        'per year',
        'annuel',
        'anual',
        'cada ano',
        'jahrlich',
      },
      const {'每年', '毎年', '매년'},
    )) {
      return 'yearly';
    }

    return null;
  }

  static String? _canonicalFollowupStatus(String rawStatus) {
    final raw = rawStatus.trim();
    if (raw.isEmpty) return null;

    final normalized = _normalizeRecurrenceText(raw);
    final compact = _compactRecurrenceText(normalized);

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'in_progress',
        'in progress',
        'progress',
        'ongoing',
        'doing',
        'active',
        'en progreso',
        'en cours',
        'in bearbeitung',
      },
      const {'进行中', '處理中', '处理中', '進行中', '進行', '진행중', '진행 중'},
    )) {
      return 'in_progress';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'done',
        'complete',
        'completed',
        'finished',
        'resolved',
        'cerrado',
        'termine',
        'erledigt',
      },
      const {'完成', '已完成', '已办结', '已辦結', '完成済み', '完了', '완료'},
    )) {
      return 'done';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'dismissed',
        'dismiss',
        'ignored',
        'ignore',
        'canceled',
        'cancelled',
        'cancel',
        'discarded',
        'annule',
        'abgebrochen',
      },
      const {'忽略', '已忽略', '取消', '已取消', '作废', '作廢', 'キャンセル', '취소', '무시'},
    )) {
      return 'dismissed';
    }

    return null;
  }

  static String? _canonicalCreateStatus(String rawStatus) {
    final raw = rawStatus.trim();
    if (raw.isEmpty) return null;

    final normalized = _normalizeRecurrenceText(raw);
    final compact = _compactRecurrenceText(normalized);

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'open',
        'todo',
        'to do',
        'pending',
        'active',
        'abierto',
        'ouvert',
        'offen',
      },
      const {'待办', '待辦', '待处理', '待處理', '未完成', '할 일', '未着手'},
    )) {
      return 'open';
    }

    if (_matchesNormalizedAlias(
      raw,
      normalized,
      compact,
      const {
        'inbox',
        'capture',
        'captured',
        'draft',
      },
      const {'收件箱', '收件匣', '草稿', '收件箱待处理'},
    )) {
      return 'inbox';
    }

    return null;
  }

  static MessageActionRecurrenceRule? _parseRecurrenceRule(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final freqRaw = _stringField(map, 'freq');
    if (freqRaw == null) return null;
    final freq = _canonicalRecurrenceFreq(freqRaw);
    if (freq == null) return null;

    final interval = (_intField(map, 'interval') ?? 1).clamp(1, 10000);
    return MessageActionRecurrenceRule(freq: freq, interval: interval);
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

  static AiSemanticDecision? tryParseMessageAction(
    String raw, {
    required DateTime nowLocal,
    required Locale locale,
    required int dayEndMinutes,
    int? morningMinutes,
    int firstDayOfWeekIndex = 1,
  }) {
    final jsonText = _extractFirstJsonObject(raw);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, Object?>.from(decoded);

    final kind = _stringField(map, 'kind');
    if (kind == null || kind.isEmpty) return null;

    final confidenceRaw = _doubleField(map, 'confidence') ?? 0.0;
    final confidence =
        confidenceRaw.isFinite ? confidenceRaw.clamp(0.0, 1.0).toDouble() : 0.0;
    final resolvedMorningMinutes = morningMinutes ?? dayEndMinutes;

    switch (kind) {
      case 'followup':
        final todoId = _stringField(map, 'todo_id');
        final newStatusRaw = _stringField(map, 'new_status');
        final newStatus = newStatusRaw == null
            ? null
            : _canonicalFollowupStatus(newStatusRaw);
        if (todoId == null || todoId.isEmpty) return null;
        if (newStatus == null) return null;
        return AiSemanticDecision(
          decision: MessageActionFollowUpDecision(
              todoId: todoId, newStatus: newStatus),
          confidence: confidence,
        );
      case 'create':
        final title = _stringField(map, 'title');
        final statusRaw = _stringField(map, 'status');
        final status =
            statusRaw == null ? null : _canonicalCreateStatus(statusRaw);
        if (title == null || title.isEmpty) return null;
        if (status == null) return null;

        DateTime? dueAtLocal;
        final dueIso = _stringField(map, 'due_local_iso');
        if (dueIso != null && dueIso.isNotEmpty) {
          try {
            dueAtLocal = DateTime.parse(dueIso);
          } catch (_) {
            dueAtLocal = null;
          }
        }

        final recurrenceRule = _parseRecurrenceRule(map['recurrence']);
        if (recurrenceRule != null && dueAtLocal == null) {
          dueAtLocal = _fallbackDueAtForRecurring(
            nowLocal,
            recurrenceRule,
            morningMinutes: resolvedMorningMinutes,
            firstDayOfWeekIndex: firstDayOfWeekIndex,
          );
        }
        final normalizedStatus =
            dueAtLocal == null ? status : (status == 'inbox' ? 'open' : status);

        return AiSemanticDecision(
          decision: MessageActionCreateDecision(
            title: title,
            status: normalizedStatus,
            dueAtLocal: dueAtLocal,
            recurrenceRule: recurrenceRule,
          ),
          confidence: confidence,
        );
      case 'none':
        return AiSemanticDecision(
          decision: const MessageActionNoneDecision(),
          confidence: confidence,
        );
    }

    return null;
  }

  static AiSemanticTimeWindow? tryParseAskAiTimeWindow(
    String raw, {
    required DateTime nowLocal,
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) {
    final jsonText = _extractFirstJsonObject(raw);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, Object?>.from(decoded);

    final kind = _stringField(map, 'kind');
    if (kind == null || kind.isEmpty || kind == 'none') return null;

    final confidenceRaw = _doubleField(map, 'confidence') ?? 0.0;
    final confidence =
        confidenceRaw.isFinite ? confidenceRaw.clamp(0.0, 1.0).toDouble() : 0.0;

    final startIso = _stringField(map, 'start_local_iso');
    final endIso = _stringField(map, 'end_local_iso');
    if (startIso == null || startIso.isEmpty) return null;
    if (endIso == null || endIso.isEmpty) return null;

    DateTime? startLocal;
    DateTime? endLocal;
    try {
      startLocal = DateTime.parse(startIso);
      endLocal = DateTime.parse(endIso);
    } catch (_) {
      return null;
    }
    if (!startLocal.isBefore(endLocal)) return null;

    return AiSemanticTimeWindow(
      kind: kind,
      confidence: confidence,
      startLocal: startLocal,
      endLocal: endLocal,
    );
  }
}
