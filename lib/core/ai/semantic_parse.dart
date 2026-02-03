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

        return AiSemanticDecision(
          decision: MessageActionCreateDecision(
            title: title,
            status: status,
            dueAtLocal: dueAtLocal,
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
