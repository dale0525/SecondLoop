import 'dart:convert';
import 'dart:typed_data';

import '../../features/attachments/platform_pdf_ocr.dart';
import '../../src/rust/api/media_annotation.dart' as rust_media_annotation;
import '../../src/rust/db.dart';
import '../ai/ai_routing.dart';
import '../backend/native_app_dir.dart';
import '../backend/native_backend.dart';

const _kOcrMarkdownLangPrefix = 'ocr_markdown:';
const _kDefaultLanguageHints = 'device_plus_en';

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
        mimeType: rendered.mimeType,
        mediaBytes: rendered.imageBytes,
        pageCountHint: normalizedPageCount,
      );
      if (cloud != null) return cloud;
    } catch (_) {}

    if (byokProfile != null) {
      try {
        final byok = await byokRunner(
          profileId: byokProfile.id,
          modelName: byokProfile.modelName,
          mimeType: rendered.mimeType,
          mediaBytes: rendered.imageBytes,
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
      mimeType: rendered.mimeType,
      mediaBytes: rendered.imageBytes,
      pageCountHint: normalizedPageCount,
    );
  } catch (_) {
    // BYOK fallback order: byok -> caller handles runtime OCR -> native OCR.
    return null;
  }
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
