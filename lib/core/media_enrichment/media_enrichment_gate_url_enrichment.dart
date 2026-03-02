part of 'media_enrichment_gate.dart';

const String _kAskAiErrorPrefix = '\u001eSL_ERROR\u001e';
const String _kAskAiMetaPrefix = '\u001eSL_META\u001e';

extension _MediaEnrichmentGateUrlEnrichmentExtension
    on _MediaEnrichmentGateState {
  List<UrlEnrichmentEnhancer> _buildUrlEnrichmentEnhancers({
    required MediaSourcePreference preference,
    required bool cloudAvailable,
    required LlmProfile? byokProfile,
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required String cloudModelName,
  }) {
    final enrichers = <UrlEnrichmentEnhancer>[];
    final orderedRoutes = mediaSourceFallbackOrder(preference);
    final conversationIdProvider =
        _loopHomeConversationIdProvider(backend, sessionKey);

    for (final route in orderedRoutes) {
      switch (route) {
        case MediaSourceRouteKind.cloudGateway:
          if (!cloudAvailable) continue;
          if (gatewayBaseUrl.trim().isEmpty ||
              cloudIdToken.trim().isEmpty ||
              cloudModelName.trim().isEmpty) {
            continue;
          }
          enrichers.add(
            _AskAiUrlEnrichmentEnhancer.cloud(
              backend: backend,
              sessionKey: sessionKey,
              conversationIdProvider: conversationIdProvider,
              gatewayBaseUrl: gatewayBaseUrl.trim(),
              cloudIdToken: cloudIdToken.trim(),
              modelName: cloudModelName.trim(),
            ),
          );
          break;
        case MediaSourceRouteKind.byok:
          if (byokProfile == null) continue;
          enrichers.add(
            _AskAiUrlEnrichmentEnhancer.byok(
              backend: backend,
              sessionKey: sessionKey,
              conversationIdProvider: conversationIdProvider,
              modelName: byokProfile.modelName,
            ),
          );
          break;
        case MediaSourceRouteKind.local:
          break;
      }
    }

    return enrichers;
  }

  Future<String> Function() _loopHomeConversationIdProvider(
    NativeAppBackend backend,
    Uint8List sessionKey,
  ) {
    Future<String>? pending;
    return () {
      pending ??= backend
          .getOrCreateLoopHomeConversation(sessionKey)
          .then((conversation) => conversation.id);
      return pending!;
    };
  }
}

enum _AskAiUrlEnrichmentRouteKind {
  cloud,
  byok,
}

final class _AskAiUrlEnrichmentEnhancer implements UrlEnrichmentEnhancer {
  _AskAiUrlEnrichmentEnhancer._({
    required this.backend,
    required Uint8List sessionKey,
    required this.conversationIdProvider,
    required this.route,
    required this.modelName,
    this.gatewayBaseUrl,
    this.cloudIdToken,
  }) : _sessionKey = Uint8List.fromList(sessionKey);

  factory _AskAiUrlEnrichmentEnhancer.cloud({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required Future<String> Function() conversationIdProvider,
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required String modelName,
  }) {
    return _AskAiUrlEnrichmentEnhancer._(
      backend: backend,
      sessionKey: sessionKey,
      conversationIdProvider: conversationIdProvider,
      route: _AskAiUrlEnrichmentRouteKind.cloud,
      modelName: modelName,
      gatewayBaseUrl: gatewayBaseUrl,
      cloudIdToken: cloudIdToken,
    );
  }

  factory _AskAiUrlEnrichmentEnhancer.byok({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required Future<String> Function() conversationIdProvider,
    required String modelName,
  }) {
    return _AskAiUrlEnrichmentEnhancer._(
      backend: backend,
      sessionKey: sessionKey,
      conversationIdProvider: conversationIdProvider,
      route: _AskAiUrlEnrichmentRouteKind.byok,
      modelName: modelName,
    );
  }

  final NativeAppBackend backend;
  final Uint8List _sessionKey;
  final Future<String> Function() conversationIdProvider;
  final _AskAiUrlEnrichmentRouteKind route;
  @override
  final String modelName;
  final String? gatewayBaseUrl;
  final String? cloudIdToken;

  @override
  String get source => switch (route) {
        _AskAiUrlEnrichmentRouteKind.cloud => 'cloud',
        _AskAiUrlEnrichmentRouteKind.byok => 'byok',
      };

  @override
  Future<UrlEnrichmentEnhancerResult?> enhance({
    required String originalUrl,
    required String finalUrl,
    required String site,
    required String? title,
    required String readableTextExcerpt,
    required String readableTextFull,
  }) async {
    final conversationId = await conversationIdProvider();
    if (conversationId.trim().isEmpty) {
      throw StateError('missing_conversation_id');
    }

    final prompt = _buildUrlEnhancementPrompt(
      originalUrl: originalUrl,
      finalUrl: finalUrl,
      site: site,
      title: title,
      readableTextExcerpt: readableTextExcerpt,
      readableTextFull: readableTextFull,
    );

    final stream = switch (route) {
      _AskAiUrlEnrichmentRouteKind.cloud => backend.askAiStreamCloudGateway(
          _sessionKey,
          conversationId,
          question: prompt,
          topK: 0,
          thisThreadOnly: true,
          gatewayBaseUrl: gatewayBaseUrl ?? '',
          idToken: cloudIdToken ?? '',
          modelName: modelName,
        ),
      _AskAiUrlEnrichmentRouteKind.byok => backend.askAiStream(
          _sessionKey,
          conversationId,
          question: prompt,
          topK: 0,
          thisThreadOnly: true,
        ),
    };

    final raw = await _collectAskAiOutput(stream);
    final parsed = _parseUrlEnhancementJson(raw);
    if (parsed == null) return null;
    return parsed;
  }

  static String _buildUrlEnhancementPrompt({
    required String originalUrl,
    required String finalUrl,
    required String site,
    required String? title,
    required String readableTextExcerpt,
    required String readableTextFull,
  }) {
    final safeTitle = (title ?? '').trim().isEmpty ? '(none)' : title!.trim();
    final summarySource = readableTextExcerpt.trim().isNotEmpty
        ? readableTextExcerpt
        : readableTextFull;
    final clippedSource = summarySource.length <= 6000
        ? summarySource
        : summarySource.substring(0, 6000);

    return '''
You are enriching shared URL content for a note-taking app.
Return ONLY a JSON object with this schema:
{
  "title": string,
  "summary": string,
  "tags": string[]
}
Rules:
- "title" should be concise and accurate.
- "summary" should be 2-4 sentences, no markdown.
- "tags" should contain 0-6 short topical tags.
- Do not include any additional keys.

original_url: $originalUrl
final_url: $finalUrl
site: $site
current_title: $safeTitle
extracted_text:
$clippedSource
''';
  }

  static Future<String> _collectAskAiOutput(Stream<String> stream) async {
    final out = StringBuffer();
    await for (final delta in stream) {
      if (delta.startsWith(_kAskAiMetaPrefix)) continue;
      if (delta.startsWith(_kAskAiErrorPrefix)) {
        final message = delta.substring(_kAskAiErrorPrefix.length).trim();
        throw StateError(message.isEmpty ? 'ask_ai_stream_error' : message);
      }
      out.write(delta);
    }
    final raw = out.toString().trim();
    if (raw.isEmpty) throw StateError('ask_ai_empty_output');
    return raw;
  }

  static UrlEnrichmentEnhancerResult? _parseUrlEnhancementJson(String raw) {
    final jsonObject = _extractFirstJsonObject(raw);
    if (jsonObject == null) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonObject);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final map = Map<String, Object?>.from(decoded);
    final title = _readString(map, 'title');
    final summary = _readString(map, 'summary');
    final tags = _readTags(map['tags']);
    if ((title ?? '').isEmpty && (summary ?? '').isEmpty && tags.isEmpty) {
      return null;
    }

    return UrlEnrichmentEnhancerResult(
      title: title,
      summary: summary,
      tags: tags,
    );
  }

  static String? _extractFirstJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;

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
      if (ch == '{') depth += 1;
      if (ch == '}') {
        depth -= 1;
        if (depth == 0) {
          return raw.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String? _readString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static List<String> _readTags(Object? raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      final dedupKey = normalized.toLowerCase();
      if (!seen.add(dedupKey)) continue;
      out.add(normalized);
      if (out.length >= 6) break;
    }
    return out;
  }
}
