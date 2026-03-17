import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/db.dart';
import '../backend/app_backend.dart';
import 'ai_routing.dart';

const int kMaxGeneratedFollowupCitations = 5;

class TodoFollowupCitationDraft {
  const TodoFollowupCitationDraft({
    required this.title,
    required this.url,
    required this.domain,
  });

  final String title;
  final String url;
  final String domain;
}

enum TodoFollowupGenerationMode {
  webSearch('web_search'),
  modelKnowledge('model_knowledge');

  const TodoFollowupGenerationMode(this.wireValue);

  final String wireValue;

  static TodoFollowupGenerationMode fromWireValue(String? raw) {
    return (raw ?? '').trim().toLowerCase() == webSearch.wireValue
        ? webSearch
        : modelKnowledge;
  }
}

class TodoFollowupSuggestionDraft {
  const TodoFollowupSuggestionDraft({
    required this.content,
    required this.mode,
    required this.citations,
  });

  final String content;
  final TodoFollowupGenerationMode mode;
  final List<TodoFollowupCitationDraft> citations;
}

Future<TodoFollowupSuggestionDraft?> requestTodoFollowupSuggestion({
  required AppBackend backend,
  required Uint8List sessionKey,
  required AskAiRouteKind route,
  required String gatewayBaseUrl,
  required String idToken,
  required String modelName,
  required String taskTitle,
  required String taskContext,
  required String localeTag,
  required TodoFollowupGenerationMode generationMode,
  required List<String> manualFollowups,
  String? status,
  int? dueAtMs,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (route == AskAiRouteKind.needsSetup) {
    return null;
  }

  final prompt = buildTodoFollowupSuggestionPrompt(
    taskTitle: taskTitle,
    taskContext: taskContext,
    localeTag: localeTag,
    generationMode: generationMode,
    manualFollowups: manualFollowups,
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
      : await backend.runAiPrompt(sessionKey, prompt: prompt).timeout(timeout);

  return parseTodoFollowupSuggestionJson(response);
}

String buildTodoFollowupSuggestionPrompt({
  required String taskTitle,
  required String taskContext,
  required String localeTag,
  required TodoFollowupGenerationMode generationMode,
  required List<String> manualFollowups,
  String? status,
  int? dueAtMs,
}) {
  final dueLocalIso = dueAtMs == null
      ? ''
      : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true)
          .toLocal()
          .toIso8601String();
  final modeLabel = generationMode == TodoFollowupGenerationMode.webSearch
      ? 'Use web search and include citations.'
      : 'No web search is available. 在正文中明确写出“未联网核实”。';
  final manualFollowupsBlock = manualFollowups.isEmpty
      ? '(none)'
      : manualFollowups.map((item) => '- ${item.trim()}').join('\n');

  return '''You are writing an information follow-up note for a todo.

Return strict JSON only in this shape:
{"content":"...","mode":"web_search|model_knowledge","citations":[{"title":"...","url":"...","domain":"..."}]}

Rules:
- Write a concise information follow-up the user can directly keep as a task update.
- Do not tell the user what to research next.
- Do not output markdown code fences.
- If mode is model_knowledge, the note must clearly say “未联网核实”.
- Citations are optional, but include up to $kMaxGeneratedFollowupCitations citations when web search is used.
- Use the same language as the task content.

$modeLabel
Locale: $localeTag
Task title: ${taskTitle.trim()}
Task status: ${(status ?? '').trim()}
Task due local ISO: $dueLocalIso
Task context:
${taskContext.trim()}

Manual follow-up notes:
$manualFollowupsBlock
''';
}

TodoFollowupSuggestionDraft? parseTodoFollowupSuggestionJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final jsonText = _extractJsonCandidate(trimmed);
  if (jsonText == null) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (_) {
    return null;
  }

  if (decoded is! Map) return null;
  final map = Map<String, Object?>.from(decoded);
  final content = (map['content'] as String?)?.trim() ?? '';
  if (content.isEmpty) return null;

  final mode = TodoFollowupGenerationMode.fromWireValue(
    (map['mode'] as String?)?.trim(),
  );

  final citations = <TodoFollowupCitationDraft>[];
  final seen = <String>{};
  final rawCitations = map['citations'];
  if (rawCitations is List) {
    for (final item in rawCitations) {
      if (item is! Map) continue;
      final next = _parseCitation(item);
      if (next == null) continue;
      final dedupeKey = '${next.domain}|${next.url}'.toLowerCase();
      if (!seen.add(dedupeKey)) continue;
      citations.add(next);
      if (citations.length >= kMaxGeneratedFollowupCitations) break;
    }
  }

  return TodoFollowupSuggestionDraft(
    content: content,
    mode: mode,
    citations: List<TodoFollowupCitationDraft>.unmodifiable(citations),
  );
}

Uri? tryParseTodoFollowupCitationUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return null;

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  if (!uri.hasAuthority) {
    return null;
  }
  return uri;
}

String buildTodoFollowupSuggestionContext({
  required Todo todo,
  required List<TodoActivity> activities,
  bool includeManualFollowupsOnly = false,
}) {
  final parts = <String>[todo.title.trim()];

  for (final activity in activities) {
    final content = (activity.content ?? '').trim();
    if (content.isEmpty) continue;
    if (includeManualFollowupsOnly) {
      if (activity.activityType != 'note') continue;
    }
    parts.add(content);
  }

  return parts.join('\n');
}

TodoFollowupCitationDraft? _parseCitation(Map<Object?, Object?> raw) {
  final title = (raw['title'] as String?)?.trim() ?? '';
  final url = (raw['url'] as String?)?.trim() ?? '';
  final domain = (raw['domain'] as String?)?.trim() ?? '';
  if (title.isEmpty || url.isEmpty || domain.isEmpty) return null;
  return TodoFollowupCitationDraft(title: title, url: url, domain: domain);
}

String? _extractJsonCandidate(String raw) {
  final fencedMatch =
      RegExp(r'```(?:json)?\s*(\{[\s\S]*\})\s*```').firstMatch(raw);
  if (fencedMatch != null) {
    return fencedMatch.group(1)?.trim();
  }

  final objectStart = raw.indexOf('{');
  final objectEnd = raw.lastIndexOf('}');
  if (objectStart != -1 && objectEnd > objectStart) {
    return raw.substring(objectStart, objectEnd + 1).trim();
  }
  return null;
}
