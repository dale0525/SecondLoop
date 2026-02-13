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

  static bool _matchesRecurrenceAlias(
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

    if (_matchesRecurrenceAlias(
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

    if (_matchesRecurrenceAlias(
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

    if (_matchesRecurrenceAlias(
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

    if (_matchesRecurrenceAlias(
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

  static DateTime _fallbackDueAtForRecurring(
    DateTime nowLocal,
    int dayEndMinutes,
  ) {
    final hour = dayEndMinutes ~/ 60;
    final minute = dayEndMinutes % 60;
    var due = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      hour,
      minute,
    );
    if (!due.isAfter(nowLocal)) {
      due = due.add(const Duration(days: 1));
    }
    return due;
  }

  static AiSemanticDecision? tryParseMessageAction(
    String raw, {
    required DateTime nowLocal,
    required Locale locale,
    required int dayEndMinutes,
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

    switch (kind) {
      case 'followup':
        final todoId = _stringField(map, 'todo_id');
        final newStatus = _stringField(map, 'new_status');
        const allowed = {'in_progress', 'done', 'dismissed'};
        if (todoId == null || todoId.isEmpty) return null;
        if (newStatus == null || !allowed.contains(newStatus)) return null;
        return AiSemanticDecision(
          decision: MessageActionFollowUpDecision(
              todoId: todoId, newStatus: newStatus),
          confidence: confidence,
        );
      case 'create':
        final title = _stringField(map, 'title');
        final status = _stringField(map, 'status');
        if (title == null || title.isEmpty) return null;
        if (status == null) return null;
        if (status != 'open' && status != 'inbox') return null;

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
          dueAtLocal = _fallbackDueAtForRecurring(nowLocal, dayEndMinutes);
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
