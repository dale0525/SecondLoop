import '../../features/attachments/platform_pdf_ocr.dart';
import 'ocr_text_quality.dart';

bool isRuntimeOcrEngine(String engine) {
  return engine.trim().toLowerCase().startsWith('desktop_rust_');
}

String buildOcrExcerptFromText(String fullText, {int maxChars = 1200}) {
  final trimmed = fullText.trim();
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars).trimRight()}…';
}

PlatformPdfOcrResult maybePreferExtractedTextForRuntimeOcr({
  required PlatformPdfOcrResult ocr,
  required String extractedFull,
  required String extractedExcerpt,
  double minScoreDelta = 12,
  int excerptMaxChars = 1200,
}) {
  if (!isRuntimeOcrEngine(ocr.engine)) return ocr;

  final full = extractedFull.trim();
  if (full.isEmpty) return ocr;

  if (!shouldPreferExtractedTextOverOcr(
    extractedText: full,
    ocrText: ocr.fullText,
    minScoreDelta: minScoreDelta,
  )) {
    return ocr;
  }

  final excerpt = extractedExcerpt.trim();
  return ocr.copyWith(
    fullText: full,
    excerpt: excerpt.isNotEmpty
        ? excerpt
        : buildOcrExcerptFromText(full, maxChars: excerptMaxChars),
    engine: '${ocr.engine}+prefer_extracted',
  );
}
