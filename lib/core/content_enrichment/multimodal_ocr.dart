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

String normalizeOcrEngineMode(String mode) {
  switch (mode.trim()) {
    case 'multimodal_llm':
      return 'multimodal_llm';
    default:
      return 'platform_native';
  }
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
}) async {
  final canUseCloud = subscriptionStatus == SubscriptionStatus.entitled &&
      mediaAnnotationConfig.providerMode == 'cloud_gateway' &&
      cloudGatewayBaseUrl.trim().isNotEmpty &&
      cloudIdToken.trim().isNotEmpty;

  if (canUseCloud) {
    return tryMultimodalOcrViaCloud(
      backend: backend,
      gatewayBaseUrl: cloudGatewayBaseUrl,
      idToken: cloudIdToken,
      modelName: cloudModelName,
      languageHints: languageHints,
      mimeType: 'application/pdf',
      mediaBytes: pdfBytes,
      pageCountHint: pageCountHint,
    );
  }

  final byokProfile = resolveMultimodalOcrByokProfile(
    profiles: llmProfiles,
    preferredProfileId: mediaAnnotationConfig.byokProfileId,
  );
  if (byokProfile == null) return null;
  return tryMultimodalOcrViaByok(
    sessionKey: sessionKey,
    profileId: byokProfile.id,
    modelName: byokProfile.modelName,
    languageHints: languageHints,
    mimeType: 'application/pdf',
    mediaBytes: pdfBytes,
    pageCountHint: pageCountHint,
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
