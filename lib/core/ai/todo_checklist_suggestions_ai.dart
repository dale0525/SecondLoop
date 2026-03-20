import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/db.dart';
import '../backend/app_backend.dart';
import 'ai_routing.dart';

const int kMaxGeneratedChecklistSuggestions = 8;

Future<List<String>> requestTodoChecklistSuggestions({
  required AppBackend backend,
  required Uint8List sessionKey,
  required AskAiRouteKind route,
  required String gatewayBaseUrl,
  required String idToken,
  required String modelName,
  required String taskTitle,
  required String taskContext,
  required String localeTag,
  String? status,
  int? dueAtMs,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (route == AskAiRouteKind.needsSetup) {
    return const <String>[];
  }

  final prompt = buildTodoChecklistSuggestionsPrompt(
    taskTitle: taskTitle,
    taskContext: taskContext,
    localeTag: localeTag,
    status: status,
    dueAtMs: dueAtMs,
  );

  final response = route == AskAiRouteKind.cloudGateway
      ? await backend
          .runAiPromptCloudGateway(
            sessionKey,
            prompt: prompt,
            gatewayBaseUrl: gatewayBaseUrl,
            idToken: idToken,
            modelName: modelName,
          )
          .timeout(timeout)
      : await backend
          .runAiPrompt(
            sessionKey,
            prompt: prompt,
          )
          .timeout(timeout);

  return parseTodoChecklistSuggestionsJson(response);
}

String buildTodoChecklistSuggestionsPrompt({
  required String taskTitle,
  required String taskContext,
  required String localeTag,
  String? status,
  int? dueAtMs,
}) {
  final dueLocalIso = dueAtMs == null
      ? ''
      : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true)
          .toLocal()
          .toIso8601String();

  return '''You are helping turn a task into a practical checklist.

Return strict JSON only in this shape:
{"suggestions":["step 1","step 2"]}

Rules:
- Suggest 0 to $kMaxGeneratedChecklistSuggestions checklist items.
- Keep each item short, concrete, and actionable.
- Do not number the items.
- Do not repeat the task title.
- Avoid trivial items like "start task" or "finish task".
- Use the same language as the task content.
- Prefer steps the user can actually complete.
- If the task is too small to break down, return an empty list.

Locale: $localeTag
Task title: ${taskTitle.trim()}
Task status: ${(status ?? '').trim()}
Task due local ISO: $dueLocalIso
Context:
${taskContext.trim()}
''';
}

List<String> parseTodoChecklistSuggestionsJson(
  String raw, {
  int maxItems = kMaxGeneratedChecklistSuggestions,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <String>[];

  final jsonText = _extractJsonCandidate(trimmed);
  if (jsonText == null) {
    return _parseChecklistSuggestionsPlainText(trimmed, maxItems: maxItems);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (_) {
    final recoveredFromLooseJson = _parseChecklistSuggestionsLooseJson(
      jsonText,
      maxItems: maxItems,
    );
    if (recoveredFromLooseJson.isNotEmpty) {
      return recoveredFromLooseJson;
    }
    return _parseChecklistSuggestionsPlainText(trimmed, maxItems: maxItems);
  }

  final rawSuggestions = switch (decoded) {
    {'suggestions': final List<dynamic> suggestions} => suggestions,
    final List<dynamic> suggestions => suggestions,
    _ => const <dynamic>[],
  };

  final normalized = <String>[];
  final seen = <String>{};
  for (final item in rawSuggestions) {
    if (item is! String) continue;
    final next = _normalizeChecklistSuggestion(item);
    if (next == null) continue;
    final dedupeKey = next.toLowerCase();
    if (!seen.add(dedupeKey)) continue;
    normalized.add(next);
    if (normalized.length >= maxItems) break;
  }

  return List<String>.unmodifiable(normalized);
}

List<String> _parseChecklistSuggestionsPlainText(
  String raw, {
  required int maxItems,
}) {
  final normalized = <String>[];
  final seen = <String>{};

  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final next = _normalizeChecklistSuggestion(line);
    if (next == null) continue;
    final dedupeKey = next.toLowerCase();
    if (!seen.add(dedupeKey)) continue;
    normalized.add(next);
    if (normalized.length >= maxItems) break;
  }

  return List<String>.unmodifiable(normalized);
}

List<String> _parseChecklistSuggestionsLooseJson(
  String raw, {
  required int maxItems,
}) {
  final normalized = <String>[];
  final seen = <String>{};

  for (final candidate in _extractLooseJsonSuggestionCandidates(raw)) {
    final next = _normalizeChecklistSuggestion(candidate);
    if (next == null) continue;
    final dedupeKey = next.toLowerCase();
    if (!seen.add(dedupeKey)) continue;
    normalized.add(next);
    if (normalized.length >= maxItems) break;
  }

  return List<String>.unmodifiable(normalized);
}

Iterable<String> _extractLooseJsonSuggestionCandidates(String raw) sync* {
  final trimmed = raw.trim();
  final arraySegments = <String>[];

  if (trimmed.startsWith('[')) {
    final listEnd = trimmed.lastIndexOf(']');
    if (listEnd != -1) {
      arraySegments.add(trimmed.substring(0, listEnd + 1));
    }
  }

  for (final key in const <String>['suggestions', 'items', 'checklist']) {
    final match = RegExp(
      '"$key"\\s*:\\s*(\\[[\\s\\S]*?\\])',
    ).firstMatch(raw);
    final segment = match?.group(1)?.trim();
    if (segment != null && segment.isNotEmpty) {
      arraySegments.add(segment);
    }
  }

  for (final segment in arraySegments) {
    for (final match in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(segment)) {
      final encoded = '"${match.group(1)}"';
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is String) {
          yield decoded;
        }
      } catch (_) {
        final fallback = match.group(1);
        if (fallback != null) {
          yield fallback;
        }
      }
    }
  }
}

String? _extractJsonCandidate(String raw) {
  final fencedMatch =
      RegExp(r'```(?:json)?\s*(\{[\s\S]*\}|\[[\s\S]*\])\s*```').firstMatch(raw);
  if (fencedMatch != null) {
    return fencedMatch.group(1)?.trim();
  }

  final objectStart = raw.indexOf('{');
  final objectEnd = raw.lastIndexOf('}');
  if (objectStart != -1 && objectEnd > objectStart) {
    return raw.substring(objectStart, objectEnd + 1).trim();
  }

  final listStart = raw.indexOf('[');
  final listEnd = raw.lastIndexOf(']');
  if (listStart != -1 && listEnd > listStart) {
    return raw.substring(listStart, listEnd + 1).trim();
  }

  return null;
}

String? _normalizeChecklistSuggestion(String raw) {
  final stripped = raw
      .replaceFirst(RegExp(r'^\s*[-*•]+\s*'), '')
      .replaceFirst(RegExp(r'^\s*\d+[\.)]\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (stripped.isEmpty) return null;
  return stripped;
}

String buildTodoChecklistSuggestionContext({
  required Todo todo,
  required List<TodoActivity> activities,
}) {
  final parts = <String>[
    todo.title.trim(),
  ];

  for (final activity in activities) {
    final content = (activity.content ?? '').trim();
    if (content.isEmpty) continue;
    parts.add(content);
    if (parts.length >= 6) break;
  }

  return parts.join('\n');
}
