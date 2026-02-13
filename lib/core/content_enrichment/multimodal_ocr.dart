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
