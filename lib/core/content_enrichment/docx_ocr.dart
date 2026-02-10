import 'dart:typed_data';

import '../../features/attachments/platform_pdf_ocr.dart';
import '../../src/rust/db.dart';
import '../ai/ai_routing.dart';
import '../backend/native_backend.dart';
import 'docx_ocr_policy.dart';
import 'multimodal_ocr.dart';

typedef TryDocxOcrImage = Future<PlatformPdfOcrResult?> Function(
  Uint8List bytes, {
  required String languageHints,
});

Future<PlatformPdfOcrResult?> tryConfiguredDocxOcr({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required Uint8List docxBytes,
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
  TryDocxOcrImage? tryRuntimeOrNativeImageOcr,
}) async {
  if (docxBytes.isEmpty) return null;

  final media = extractDocxPrimaryImage(docxBytes);
  if (media == null || media.bytes.isEmpty) return null;

  final normalizedPageCount = pageCountHint < 1 ? 1 : pageCountHint;
  final multimodal = await tryConfiguredMultimodalMediaOcr(
    backend: backend,
    sessionKey: sessionKey,
    mimeType: media.mimeType,
    mediaBytes: media.bytes,
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
  if (multimodal != null) return multimodal;

  return (tryRuntimeOrNativeImageOcr ?? PlatformPdfOcr.tryOcrImageBytes)(
    media.bytes,
    languageHints: languageHints,
  );
}
