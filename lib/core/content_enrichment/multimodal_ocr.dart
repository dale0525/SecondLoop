import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/attachments/platform_pdf_ocr.dart';
import '../../src/rust/api/media_annotation.dart' as rust_media_annotation;
import '../../src/rust/db.dart';
import '../ai/ai_routing.dart';
import '../backend/native_app_dir.dart';
import '../backend/native_backend.dart';

const _kOcrMarkdownLangPrefix = 'ocr_markdown:';
const _kVideoExtractLangPrefix = 'video_extract:';
const _kDefaultLanguageHints = 'device_plus_en';
const _kCloudDetachedRequestIdPayloadKey = 'secondloop_cloud_request_id';
final RegExp _kCloudDetachedRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9:_-]{5,127}$',
);

typedef TryCloudOcrForPdf = Future<PlatformPdfOcrResult?> Function({
  required String mimeType,
  required Uint8List mediaBytes,
  required int pageCountHint,
});

typedef TryByokOcrForPdf = Future<PlatformPdfOcrResult?> Function({
  required String profileId,
  required String modelName,
  required String mimeType,
  required Uint8List mediaBytes,
  required int pageCountHint,
});

typedef TryCloudVideoInsight = Future<MultimodalVideoInsight?> Function({
  required String mimeType,
  required Uint8List mediaBytes,
});

typedef TryByokVideoInsight = Future<MultimodalVideoInsight?> Function({
  required String profileId,
  required String modelName,
  required String mimeType,
  required Uint8List mediaBytes,
});

final class MultimodalVideoInsight {
  const MultimodalVideoInsight({
    required this.contentKind,
    required this.summary,
    required this.knowledgeMarkdown,
    required this.videoDescription,
    required this.engine,
  });

  final String contentKind;
  final String summary;
  final String knowledgeMarkdown;
  final String videoDescription;
  final String engine;

  bool get hasAny =>
      summary.isNotEmpty ||
      knowledgeMarkdown.isNotEmpty ||
      videoDescription.isNotEmpty;
}

String normalizeOcrEngineMode(String mode) {
  switch (mode.trim()) {
    case 'multimodal_llm':
      return 'multimodal_llm';
    default:
      return 'platform_native';
  }
}

bool canUseCloudMultimodalOcr({
  required SubscriptionStatus subscriptionStatus,
  required MediaAnnotationConfig mediaAnnotationConfig,
  required String cloudGatewayBaseUrl,
  required String cloudIdToken,
}) {
  return subscriptionStatus == SubscriptionStatus.entitled &&
      cloudGatewayBaseUrl.trim().isNotEmpty &&
      cloudIdToken.trim().isNotEmpty;
}

bool shouldAttemptMultimodalPdfOcr({
  required String ocrEngineMode,
  required SubscriptionStatus subscriptionStatus,
  required MediaAnnotationConfig mediaAnnotationConfig,
  required String cloudGatewayBaseUrl,
  required String cloudIdToken,
}) {
  if (normalizeOcrEngineMode(ocrEngineMode) == 'multimodal_llm') return true;
  return canUseCloudMultimodalOcr(
    subscriptionStatus: subscriptionStatus,
    mediaAnnotationConfig: mediaAnnotationConfig,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    cloudIdToken: cloudIdToken,
  );
}

LlmProfile? resolveMultimodalOcrByokProfile({
  required List<LlmProfile> profiles,
  String? preferredProfileId,
}) {
  final preferred = preferredProfileId?.trim() ?? '';
  if (preferred.isNotEmpty) {
    for (final profile in profiles) {
      if (profile.id == preferred &&
          profile.providerType == 'openai-compatible') {
        return profile;
      }
    }
  }
  for (final profile in profiles) {
    if (!profile.isActive) continue;
    if (profile.providerType != 'openai-compatible') continue;
    return profile;
  }
  return null;
}

Future<PlatformPdfOcrResult?> tryMultimodalOcrViaByok({
  required Uint8List sessionKey,
  required String profileId,
  required String modelName,
  required String languageHints,
  required String mimeType,
  required Uint8List mediaBytes,
  int pageCountHint = 1,
}) async {
  if (mediaBytes.isEmpty) return null;
  final appDir = await getNativeAppDir();
  final payloadJson = await rust_media_annotation.mediaAnnotationByokProfile(
    appDir: appDir,
    key: sessionKey,
    profileId: profileId,
    localDay: _formatLocalDayKey(DateTime.now()),
    lang: _buildOcrLang(languageHints),
    mimeType: mimeType,
    imageBytes: mediaBytes,
  );
  final markdown = extractOcrMarkdownFromMediaAnnotationPayload(payloadJson);
  if (markdown == null || markdown.isEmpty) return null;

  final pages = pageCountHint < 1 ? 1 : pageCountHint;
  return PlatformPdfOcrResult(
    fullText: markdown,
    excerpt: _buildExcerpt(markdown),
    engine: 'multimodal_byok_ocr_markdown:$modelName',
    isTruncated: false,
    pageCount: pages,
    processedPages: pages,
  );
}

Future<PlatformPdfOcrResult?> tryMultimodalOcrViaCloud({
  required NativeAppBackend backend,
  required String gatewayBaseUrl,
  required String idToken,
  required String modelName,
  required String languageHints,
  required String mimeType,
  required Uint8List mediaBytes,
  int pageCountHint = 1,
}) async {
  if (mediaBytes.isEmpty) return null;
  final payloadJson = await backend.mediaAnnotationCloudGateway(
    gatewayBaseUrl: gatewayBaseUrl,
    idToken: idToken,
    modelName: modelName,
    lang: _buildOcrLang(languageHints),
    mimeType: mimeType,
    imageBytes: mediaBytes,
  );
  final markdown = extractOcrMarkdownFromMediaAnnotationPayload(payloadJson);
  if (markdown == null || markdown.isEmpty) return null;

  final detachedRequestId =
      _extractCloudDetachedRequestIdFromMediaPayloadJson(payloadJson);
  if (detachedRequestId != null) {
    unawaited(
      _ackCloudDetachedChatJob(
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        requestId: detachedRequestId,
      ),
    );
  }

  final pages = pageCountHint < 1 ? 1 : pageCountHint;
  return PlatformPdfOcrResult(
    fullText: markdown,
    excerpt: _buildExcerpt(markdown),
    engine: 'multimodal_cloud_ocr_markdown:$modelName',
    isTruncated: false,
    pageCount: pages,
    processedPages: pages,
  );
}

Future<PlatformPdfOcrResult?> tryConfiguredMultimodalMediaOcr({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String mimeType,
  required Uint8List mediaBytes,
  required int pageCountHint,
  required String languageHints,
  required SubscriptionStatus subscriptionStatus,
  required MediaAnnotationConfig mediaAnnotationConfig,
  required List<LlmProfile> llmProfiles,
  required String cloudGatewayBaseUrl,
  required String cloudIdToken,
  required String cloudModelName,
  TryCloudOcrForPdf? tryCloudOcr,
  TryByokOcrForPdf? tryByokOcr,
}) async {
  if (mediaBytes.isEmpty) return null;

  final canUseCloud = canUseCloudMultimodalOcr(
    subscriptionStatus: subscriptionStatus,
    mediaAnnotationConfig: mediaAnnotationConfig,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    cloudIdToken: cloudIdToken,
  );

  final byokProfile = resolveMultimodalOcrByokProfile(
    profiles: llmProfiles,
    preferredProfileId: mediaAnnotationConfig.byokProfileId,
  );

  if (!canUseCloud && byokProfile == null) {
    return null;
  }

  final normalizedPageCount = pageCountHint < 1 ? 1 : pageCountHint;

  final cloudRunner = tryCloudOcr ??
      ({
        required String mimeType,
        required Uint8List mediaBytes,
        required int pageCountHint,
      }) {
        return tryMultimodalOcrViaCloud(
          backend: backend,
          gatewayBaseUrl: cloudGatewayBaseUrl,
          idToken: cloudIdToken,
          modelName: cloudModelName,
          languageHints: languageHints,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
          pageCountHint: pageCountHint,
        );
      };

  final byokRunner = tryByokOcr ??
      ({
        required String profileId,
        required String modelName,
        required String mimeType,
        required Uint8List mediaBytes,
        required int pageCountHint,
      }) {
        return tryMultimodalOcrViaByok(
          sessionKey: sessionKey,
          profileId: profileId,
          modelName: modelName,
          languageHints: languageHints,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
          pageCountHint: pageCountHint,
        );
      };

  if (canUseCloud) {
    try {
      final cloud = await cloudRunner(
        mimeType: mimeType,
        mediaBytes: mediaBytes,
        pageCountHint: normalizedPageCount,
      );
      if (cloud != null) return cloud;
    } catch (_) {}

    if (byokProfile != null) {
      try {
        final byok = await byokRunner(
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
          pageCountHint: normalizedPageCount,
        );
        if (byok != null) return byok;
      } catch (_) {}
    }
    // Cloud path fallback order: cloud -> byok (if available) -> caller handles
    // runtime OCR -> native OCR.
    return null;
  }

  if (byokProfile == null) return null;
  try {
    return await byokRunner(
      profileId: byokProfile.id,
      modelName: byokProfile.modelName,
      mimeType: mimeType,
      mediaBytes: mediaBytes,
      pageCountHint: normalizedPageCount,
    );
  } catch (_) {
    // BYOK fallback order: byok -> caller handles runtime OCR -> native OCR.
    return null;
  }
}

Future<MultimodalVideoInsight?> tryMultimodalVideoInsightViaByok({
  required Uint8List sessionKey,
  required String profileId,
  required String modelName,
  required String languageHints,
  required String mimeType,
  required Uint8List mediaBytes,
}) async {
  if (mediaBytes.isEmpty) return null;
  final appDir = await getNativeAppDir();
  final payloadJson = await rust_media_annotation.mediaAnnotationByokProfile(
    appDir: appDir,
    key: sessionKey,
    profileId: profileId,
    localDay: _formatLocalDayKey(DateTime.now()),
    lang: _buildVideoExtractLang(languageHints),
    mimeType: mimeType,
    imageBytes: mediaBytes,
  );
  return extractMultimodalVideoInsight(
    payloadJson,
    defaultEngine: 'multimodal_byok_video_extract:$modelName',
  );
}

Future<MultimodalVideoInsight?> tryMultimodalVideoInsightViaCloud({
  required NativeAppBackend backend,
  required String gatewayBaseUrl,
  required String idToken,
  required String modelName,
  required String languageHints,
  required String mimeType,
  required Uint8List mediaBytes,
}) async {
  if (mediaBytes.isEmpty) return null;
  final payloadJson = await backend.mediaAnnotationCloudGateway(
    gatewayBaseUrl: gatewayBaseUrl,
    idToken: idToken,
    modelName: modelName,
    lang: _buildVideoExtractLang(languageHints),
    mimeType: mimeType,
    imageBytes: mediaBytes,
  );

  final detachedRequestId =
      _extractCloudDetachedRequestIdFromMediaPayloadJson(payloadJson);
  if (detachedRequestId != null) {
    unawaited(
      _ackCloudDetachedChatJob(
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        requestId: detachedRequestId,
      ),
    );
  }

  return extractMultimodalVideoInsight(
    payloadJson,
    defaultEngine: 'multimodal_cloud_video_extract:$modelName',
  );
}

Future<MultimodalVideoInsight?> tryConfiguredMultimodalVideoInsight({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String mimeType,
  required Uint8List mediaBytes,
  required String languageHints,
  required SubscriptionStatus subscriptionStatus,
  required MediaAnnotationConfig mediaAnnotationConfig,
  required List<LlmProfile> llmProfiles,
  required String cloudGatewayBaseUrl,
  required String cloudIdToken,
  required String cloudModelName,
  TryCloudVideoInsight? tryCloudInsight,
  TryByokVideoInsight? tryByokInsight,
}) async {
  if (mediaBytes.isEmpty) return null;

  final canUseCloud = canUseCloudMultimodalOcr(
    subscriptionStatus: subscriptionStatus,
    mediaAnnotationConfig: mediaAnnotationConfig,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    cloudIdToken: cloudIdToken,
  );

  final byokProfile = resolveMultimodalOcrByokProfile(
    profiles: llmProfiles,
    preferredProfileId: mediaAnnotationConfig.byokProfileId,
  );

  if (!canUseCloud && byokProfile == null) return null;

  final cloudRunner = tryCloudInsight ??
      ({
        required String mimeType,
        required Uint8List mediaBytes,
      }) {
        return tryMultimodalVideoInsightViaCloud(
          backend: backend,
          gatewayBaseUrl: cloudGatewayBaseUrl,
          idToken: cloudIdToken,
          modelName: cloudModelName,
          languageHints: languageHints,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
        );
      };

  final byokRunner = tryByokInsight ??
      ({
        required String profileId,
        required String modelName,
        required String mimeType,
        required Uint8List mediaBytes,
      }) {
        return tryMultimodalVideoInsightViaByok(
          sessionKey: sessionKey,
          profileId: profileId,
          modelName: modelName,
          languageHints: languageHints,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
        );
      };

  if (canUseCloud) {
    try {
      final cloud = await cloudRunner(
        mimeType: mimeType,
        mediaBytes: mediaBytes,
      );
      if (cloud != null) return cloud;
    } catch (_) {}

    if (byokProfile != null) {
      try {
        final byok = await byokRunner(
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
          mimeType: mimeType,
          mediaBytes: mediaBytes,
        );
        if (byok != null) return byok;
      } catch (_) {}
    }
    return null;
  }

  if (byokProfile == null) return null;
  try {
    return await byokRunner(
      profileId: byokProfile.id,
      modelName: byokProfile.modelName,
      mimeType: mimeType,
      mediaBytes: mediaBytes,
    );
  } catch (_) {
    return null;
  }
}

MultimodalVideoInsight? mergeMultimodalVideoInsights(
  Iterable<MultimodalVideoInsight?> insights, {
  int maxSummaryChars = 1024,
  int maxKnowledgeChars = 12 * 1024,
  int maxDescriptionChars = 12 * 1024,
}) {
  final normalized = insights
      .whereType<MultimodalVideoInsight>()
      .where((insight) => insight.hasAny)
      .toList(growable: false);
  if (normalized.isEmpty) return null;

  final summary = _mergeUniqueMultimodalInsightBlocks(
    normalized.map((insight) => insight.summary),
    maxChars: maxSummaryChars,
  );
  final knowledgeMarkdown = _mergeUniqueMultimodalInsightBlocks(
    normalized.map((insight) => insight.knowledgeMarkdown),
    maxChars: maxKnowledgeChars,
  );
  final videoDescription = _mergeUniqueMultimodalInsightBlocks(
    normalized.map((insight) => insight.videoDescription),
    maxChars: maxDescriptionChars,
  );

  var knowledgeVotes = 0;
  var nonKnowledgeVotes = 0;
  for (final insight in normalized) {
    final contentKind = _normalizeVideoContentKind(insight.contentKind);
    if (contentKind == 'knowledge') {
      knowledgeVotes += 1;
      continue;
    }
    if (contentKind == 'non_knowledge') {
      nonKnowledgeVotes += 1;
      continue;
    }

    final hasKnowledge = insight.knowledgeMarkdown.trim().isNotEmpty;
    final hasDescription = insight.videoDescription.trim().isNotEmpty;
    if (hasKnowledge && !hasDescription) {
      knowledgeVotes += 1;
    } else if (hasDescription && !hasKnowledge) {
      nonKnowledgeVotes += 1;
    }
  }

  var resolvedContentKind = 'unknown';
  if (knowledgeVotes > nonKnowledgeVotes) {
    resolvedContentKind = 'knowledge';
  } else if (nonKnowledgeVotes > knowledgeVotes) {
    resolvedContentKind = 'non_knowledge';
  } else {
    for (final insight in normalized) {
      final normalizedKind = _normalizeVideoContentKind(insight.contentKind);
      if (normalizedKind != 'unknown') {
        resolvedContentKind = normalizedKind;
        break;
      }
    }
  }

  if (resolvedContentKind == 'unknown') {
    if (knowledgeMarkdown.isNotEmpty && videoDescription.isEmpty) {
      resolvedContentKind = 'knowledge';
    } else if (videoDescription.isNotEmpty && knowledgeMarkdown.isEmpty) {
      resolvedContentKind = 'non_knowledge';
    }
  }

  final fallbackSummary = _firstNonEmptyString(<String>[
    summary,
    _buildExcerpt(knowledgeMarkdown, maxChars: 240),
    _buildExcerpt(videoDescription, maxChars: 240),
  ]);

  return MultimodalVideoInsight(
    contentKind: resolvedContentKind,
    summary: fallbackSummary,
    knowledgeMarkdown: knowledgeMarkdown,
    videoDescription: videoDescription,
    engine: _dominantNonEmptyMultimodalEngine(
      normalized.map((insight) => insight.engine),
    ),
  );
}

Future<PlatformPdfOcrResult?> tryConfiguredMultimodalPdfOcr({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required Uint8List pdfBytes,
  required int pageCountHint,
  required String languageHints,
  required SubscriptionStatus subscriptionStatus,
  required MediaAnnotationConfig mediaAnnotationConfig,
  required List<LlmProfile> llmProfiles,
  required String cloudGatewayBaseUrl,
  required String cloudIdToken,
  required String cloudModelName,
  Future<PlatformPdfRenderedImage?> Function(
    Uint8List bytes, {
    PlatformPdfRenderPreset preset,
  })? renderPdfToImage,
  TryCloudOcrForPdf? tryCloudOcr,
  TryByokOcrForPdf? tryByokOcr,
}) async {
  final rendered =
      await (renderPdfToImage ?? PlatformPdfRender.tryRenderPdfToLongImage)(
    pdfBytes,
    preset: PlatformPdfRenderPreset.common,
  );
  if (rendered == null || rendered.imageBytes.isEmpty) {
    return null;
  }

  final normalizedPageCount = rendered.processedPages > 0
      ? rendered.processedPages
      : (rendered.pageCount > 0 ? rendered.pageCount : pageCountHint);

  return tryConfiguredMultimodalMediaOcr(
    backend: backend,
    sessionKey: sessionKey,
    mimeType: rendered.mimeType,
    mediaBytes: rendered.imageBytes,
    pageCountHint: normalizedPageCount,
    languageHints: languageHints,
    subscriptionStatus: subscriptionStatus,
    mediaAnnotationConfig: mediaAnnotationConfig,
    llmProfiles: llmProfiles,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    cloudIdToken: cloudIdToken,
    cloudModelName: cloudModelName,
    tryCloudOcr: tryCloudOcr,
    tryByokOcr: tryByokOcr,
  );
}

MultimodalVideoInsight? extractMultimodalVideoInsight(
  String payloadJson, {
  required String defaultEngine,
}) {
  final raw = payloadJson.trim();
  if (raw.isEmpty) return null;

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final payload = Map<String, Object?>.from(decoded);

    var contentKind = _normalizeVideoContentKind(
      _firstNonEmptyJsonString(
        payload,
        const <String>['video_content_kind', 'content_kind'],
      ),
    );

    final summary = _firstNonEmptyJsonString(
      payload,
      const <String>['video_summary', 'summary', 'caption_long'],
    );

    var knowledgeMarkdown = _normalizeMarkdownValue(
      _firstNonEmptyJsonString(
        payload,
        const <String>[
          'knowledge_markdown',
          'knowledge_markdown_full',
          'knowledge_markdown_excerpt',
        ],
      ),
    );

    var videoDescription = _firstNonEmptyJsonString(
      payload,
      const <String>[
        'video_description',
        'video_description_full',
        'video_description_excerpt',
      ],
    );

    final normalizedFullText = _normalizeMarkdownValue(
      _firstNonEmptyJsonString(
        payload,
        const <String>['full_text', 'ocr_text'],
      ),
    );

    if (contentKind == 'knowledge' && knowledgeMarkdown.isEmpty) {
      knowledgeMarkdown = normalizedFullText;
    }
    if (contentKind == 'non_knowledge' && videoDescription.isEmpty) {
      videoDescription = normalizedFullText;
    }

    if (contentKind == 'unknown') {
      if (knowledgeMarkdown.isNotEmpty && videoDescription.isEmpty) {
        contentKind = 'knowledge';
      } else if (videoDescription.isNotEmpty && knowledgeMarkdown.isEmpty) {
        contentKind = 'non_knowledge';
      }
    }

    final fallbackSummary = _firstNonEmptyString(
      <String>[
        summary,
        _buildExcerpt(knowledgeMarkdown, maxChars: 240),
        _buildExcerpt(videoDescription, maxChars: 240),
        _buildExcerpt(normalizedFullText, maxChars: 240),
      ],
    );

    final engine = _firstNonEmptyString(
      <String>[
        _firstNonEmptyJsonString(
          payload,
          const <String>['video_extract_engine', 'engine', 'model'],
        ),
        defaultEngine,
      ],
    );

    final insight = MultimodalVideoInsight(
      contentKind: contentKind,
      summary: fallbackSummary,
      knowledgeMarkdown: knowledgeMarkdown,
      videoDescription: videoDescription,
      engine: engine,
    );

    if (contentKind == 'unknown' && !insight.hasAny) return null;
    return insight;
  } catch (_) {
    return null;
  }
}

String _normalizeVideoContentKind(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'knowledge':
      return 'knowledge';
    case 'non_knowledge':
      return 'non_knowledge';
    default:
      return 'unknown';
  }
}

String _firstNonEmptyJsonString(
  Map<String, Object?> payload,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = payload[key];
    if (raw == null) continue;
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') continue;
    return value;
  }
  return '';
}

String _firstNonEmptyString(List<String> values) {
  for (final raw in values) {
    final value = raw.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _mergeUniqueMultimodalInsightBlocks(
  Iterable<String> values, {
  required int maxChars,
}) {
  final seen = <String>{};
  final unique = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (!seen.add(value)) continue;
    unique.add(value);
  }
  if (unique.isEmpty) return '';
  final merged = unique.join('\n\n');
  if (maxChars <= 0) return '';
  return _buildExcerpt(merged, maxChars: maxChars);
}

String _dominantNonEmptyMultimodalEngine(Iterable<String> engines) {
  final counts = <String, int>{};
  for (final raw in engines) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return '';

  var bestEngine = '';
  var bestCount = -1;
  counts.forEach((engine, count) {
    if (count > bestCount) {
      bestEngine = engine;
      bestCount = count;
    }
  });
  return bestEngine;
}

String? extractOcrMarkdownFromMediaAnnotationPayload(String payloadJson) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) {
      final value = decoded['ocr_text'];
      if (value is String) {
        final normalized = _normalizeMarkdownValue(value);
        if (normalized.isNotEmpty) return normalized;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

String? _extractCloudDetachedRequestIdFromMediaPayloadJson(String payloadJson) {
  final raw = payloadJson.trim();
  if (raw.isEmpty) return null;

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final requestId =
        (decoded[_kCloudDetachedRequestIdPayloadKey] ?? '').toString().trim();
    if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId)) {
      return null;
    }
    return requestId;
  } catch (_) {
    return null;
  }
}

Uri? _buildCloudDetachedAckUri(String gatewayBaseUrl, String requestId) {
  final base = gatewayBaseUrl.trim();
  final normalizedRequestId = requestId.trim();
  if (base.isEmpty || normalizedRequestId.isEmpty) return null;

  final normalizedBase = base.replaceFirst(RegExp(r'/+$'), '');
  try {
    return Uri.parse('$normalizedBase/v1/chat/jobs/$normalizedRequestId/ack');
  } catch (_) {
    return null;
  }
}

Future<void> _ackCloudDetachedChatJob({
  required String gatewayBaseUrl,
  required String idToken,
  required String requestId,
}) async {
  if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId.trim())) return;

  final uri = _buildCloudDetachedAckUri(gatewayBaseUrl, requestId);
  if (uri == null) return;

  final token = idToken.trim();
  if (token.isEmpty) return;

  const retryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
  ];

  for (final delay in retryDelays) {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>().timeout(const Duration(seconds: 6));

      if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
          resp.statusCode == 404) {
        return;
      }
      if (resp.statusCode != 409) {
        return;
      }
    } catch (_) {
      // Best-effort only.
    } finally {
      client.close(force: true);
    }
  }
}

String _buildOcrLang(String languageHints) {
  final normalizedHints = languageHints.trim().isEmpty
      ? _kDefaultLanguageHints
      : languageHints.trim();
  return '$_kOcrMarkdownLangPrefix$normalizedHints';
}

String _buildVideoExtractLang(String languageHints) {
  final normalizedHints = languageHints.trim().isEmpty
      ? _kDefaultLanguageHints
      : languageHints.trim();
  return '$_kVideoExtractLangPrefix$normalizedHints';
}

String _normalizeMarkdownValue(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  final firstBreak = trimmed.indexOf('\n');
  if (firstBreak < 0) return trimmed;
  final rest = trimmed.substring(firstBreak + 1).trim();
  if (!rest.endsWith('```')) return rest;
  final lastFence = rest.lastIndexOf('```');
  if (lastFence <= 0) return rest;
  return rest.substring(0, lastFence).trim();
}

String _buildExcerpt(String fullText, {int maxChars = 1200}) {
  final trimmed = fullText.trim();
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars).trimRight()}…';
}

String _formatLocalDayKey(DateTime value) {
  final dt = value.toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
