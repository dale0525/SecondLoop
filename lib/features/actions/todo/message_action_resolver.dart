import 'package:flutter/widgets.dart';

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

final class MessageActionCreateDecision extends MessageActionDecision {
  const MessageActionCreateDecision({
    required this.title,
    required this.status,
    this.dueAtLocal,
  });

  final String title;
  final String status; // "open" | "inbox"
  final DateTime? dueAtLocal;
}

class MessageActionResolver {
  static final RegExp _todoPrefix =
      RegExp(r'^\s*todo\s*[:：]\s*(.+)$', caseSensitive: false);
  static final RegExp _checkboxPrefix = RegExp(r'^\s*[-*]\s*\[\s*\]\s*(.+)$');
  static final RegExp _time24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final RegExp _timeAmPm =
      RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);

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

    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[,，:：\-–—\s]+'), '').trim();
    return out;
  }

  static MessageActionDecision resolve(
    String text, {
    required Locale locale,
    required DateTime nowLocal,
    required int dayEndMinutes,
    required List<TodoLinkTarget> openTodoTargets,
    List<TodoThreadMatch> semanticMatches = const <TodoThreadMatch>[],
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return const MessageActionNoneDecision();

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

    // Create (new todo)
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
          : null;
      return MessageActionCreateDecision(
        title: structuredTitle,
        status: dueAtLocal == null ? 'inbox' : 'open',
        dueAtLocal: dueAtLocal,
      );
    }

    final isDoneOrDismiss = updateIntent.isExplicit &&
        (updateIntent.newStatus == 'done' ||
            updateIntent.newStatus == 'dismissed');
    if (isDoneOrDismiss) {
      return const MessageActionNoneDecision();
    }

    if (time == null) return const MessageActionNoneDecision();
    if (time.candidates.length != 1) return const MessageActionNoneDecision();

    final dueAtLocal = time.candidates.single.dueAtLocal;
    final title = _stripTimeDecorations(raw, time);
    if (title.isEmpty) return const MessageActionNoneDecision();

    return MessageActionCreateDecision(
      title: title,
      status: 'open',
      dueAtLocal: dueAtLocal,
    );
  }
}
