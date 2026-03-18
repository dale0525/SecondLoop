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

  if (route == AskAiRouteKind.cloudGateway && idToken.trim().isEmpty) {
    throw StateError('Cloud follow-up requests require a non-empty ID token');
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

  return parseTodoFollowupSuggestionJson(
    response,
    localeTag: localeTag,
  );
}

bool _isZhLocaleTag(String localeTag) {
  return localeTag.trim().toLowerCase().startsWith('zh');
}

String todoFollowupModelKnowledgeDisclosureForLocale(String localeTag) {
  return _isZhLocaleTag(localeTag) ? '未联网核实' : 'Not verified online';
}

bool _hasTodoFollowupModelKnowledgeDisclosure(
  String content, {
  required String localeTag,
}) {
  final normalized = content.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (_isZhLocaleTag(localeTag)) {
    return content
        .contains(todoFollowupModelKnowledgeDisclosureForLocale(localeTag));
  }
  return normalized.contains(
    todoFollowupModelKnowledgeDisclosureForLocale(localeTag).toLowerCase(),
  );
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
  final disclosure = todoFollowupModelKnowledgeDisclosureForLocale(localeTag);
  final modeLabel = generationMode == TodoFollowupGenerationMode.webSearch
      ? 'Use web search and include citations.'
      : _isZhLocaleTag(localeTag)
          ? 'No web search is available. 在正文中明确写出“$disclosure”。'
          : 'No web search is available. Explicitly include "$disclosure" in the note.';
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
- Write the content field in the user's current app language${localeTag.trim().isEmpty ? '' : ' ($localeTag)'}. 
- If mode is model_knowledge, the note must clearly include "$disclosure".
- Citations are optional, but include up to $kMaxGeneratedFollowupCitations citations when web search is used.

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

TodoFollowupSuggestionDraft? parseTodoFollowupSuggestionJson(
  String raw, {
  String localeTag = 'en-US',
}) {
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
  if (mode == TodoFollowupGenerationMode.modelKnowledge &&
      !_hasTodoFollowupModelKnowledgeDisclosure(
        content,
        localeTag: localeTag,
      )) {
    return null;
  }

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

  if (mode == TodoFollowupGenerationMode.webSearch && citations.isEmpty) {
    return null;
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
  if (title.isEmpty || url.isEmpty) return null;

  final uri = tryParseTodoFollowupCitationUrl(url);
  final domain = uri?.host.trim().toLowerCase() ?? '';
  if (domain.isEmpty) return null;

  return TodoFollowupCitationDraft(
    title: title,
    url: uri.toString(),
    domain: domain,
  );
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
