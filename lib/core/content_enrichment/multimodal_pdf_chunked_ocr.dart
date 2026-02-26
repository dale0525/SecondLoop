import 'dart:typed_data';

import '../../features/attachments/platform_pdf_ocr.dart';

typedef ChunkedPdfMediaOcrRunner = Future<PlatformPdfOcrResult?> Function({
  required String mimeType,
  required Uint8List mediaBytes,
  required int pageCountHint,
});

typedef ChunkedPdfEngineResolver = String Function(Iterable<String> engines);
typedef ChunkedPdfExcerptBuilder = String Function(String fullText);

Future<PlatformPdfOcrResult?> runChunkedMultimodalPdfOcr({
  required Uint8List pdfBytes,
  required int pageCountHint,
  required int chunkSize,
  required Future<PlatformPdfRenderedImage?> Function(
    Uint8List bytes, {
    PlatformPdfRenderPreset preset,
  }) renderPdfToImage,
  required ChunkedPdfMediaOcrRunner runChunkMediaOcr,
  required ChunkedPdfEngineResolver resolveDominantEngine,
  required ChunkedPdfExcerptBuilder buildExcerpt,
}) async {
  if (pdfBytes.isEmpty) return null;
  final normalizedChunkSize = chunkSize < 1 ? 1 : chunkSize;
  var totalPages = pageCountHint > 0 ? pageCountHint : 1;
  var cursor = 1;

  final chunkTexts = <String>[];
  final engines = <String>[];
  final completedRanges = <Map<String, int>>[];
  final failedRanges = <Map<String, int>>[];
  final retryHints = <String>{};
  var processedTotal = 0;
  var anyTruncated = false;
  var retryAttempted = false;
  var retryAttempts = 0;

  Map<String, int> range(int startPage, int endPage) {
    if (endPage < startPage) return <String, int>{};
    return <String, int>{
      'start_page': startPage,
      'end_page': endPage,
    };
  }

  while (cursor <= totalPages) {
    final remaining = totalPages - cursor + 1;
    final chunkMaxPages =
        remaining < normalizedChunkSize ? remaining : normalizedChunkSize;
    final preset = PlatformPdfRenderPreset.common.copyWith(
      maxPages: chunkMaxPages,
      startPage: cursor,
    );

    final rendered = await renderPdfToImage(
      pdfBytes,
      preset: preset,
    );

    var chunkUpperBound = cursor + chunkMaxPages - 1;
    if (rendered != null && rendered.pageCount > 0) {
      totalPages = rendered.pageCount;
      if (chunkUpperBound > totalPages) {
        chunkUpperBound = totalPages;
      }
    } else if (chunkUpperBound > totalPages) {
      chunkUpperBound = totalPages;
    }

    if (chunkUpperBound < cursor) {
      break;
    }

    if (rendered == null || rendered.imageBytes.isEmpty) {
      final failed = range(cursor, chunkUpperBound);
      if (failed.isNotEmpty) failedRanges.add(failed);
      cursor = chunkUpperBound + 1;
      continue;
    }

    final renderedProcessed = rendered.processedPages > 0
        ? rendered.processedPages
        : (chunkUpperBound - cursor + 1);
    final normalizedChunkPages = renderedProcessed.clamp(1, chunkMaxPages);

    final chunkResult = await runChunkMediaOcr(
      mimeType: rendered.mimeType,
      mediaBytes: rendered.imageBytes,
      pageCountHint: normalizedChunkPages,
    );

    if (chunkResult == null) {
      final failed = range(cursor, chunkUpperBound);
      if (failed.isNotEmpty) failedRanges.add(failed);
      cursor = chunkUpperBound + 1;
      continue;
    }

    final chunkWidth = chunkUpperBound - cursor + 1;
    final resolvedProcessed = chunkResult.processedPages > 0
        ? chunkResult.processedPages.clamp(1, chunkWidth)
        : chunkWidth;
    final chunkEnd = cursor + resolvedProcessed - 1;

    final completed = range(cursor, chunkEnd);
    if (completed.isNotEmpty) completedRanges.add(completed);
    if (chunkEnd < chunkUpperBound) {
      final failed = range(chunkEnd + 1, chunkUpperBound);
      if (failed.isNotEmpty) failedRanges.add(failed);
    }

    processedTotal += resolvedProcessed;
    anyTruncated = anyTruncated || chunkResult.isTruncated;
    retryAttempted = retryAttempted || chunkResult.retryAttempted;
    retryAttempts += chunkResult.retryAttempts;
    retryHints.addAll(
      chunkResult.retryHintsTried
          .map((hint) => hint.trim())
          .where((hint) => hint.isNotEmpty),
    );
    engines.add(chunkResult.engine.trim());

    final text = chunkResult.fullText.trim();
    if (text.isNotEmpty) {
      chunkTexts.add('[pages $cursor-$chunkEnd]\n$text');
    }
    cursor = chunkUpperBound + 1;
  }

  if (processedTotal <= 0) return null;

  final mergedText = chunkTexts.join('\n\n').trim();
  final dominantEngine = resolveDominantEngine(engines);
  final partial = failedRanges.isNotEmpty || processedTotal < totalPages;
  final resolvedEngine = partial
      ? '${dominantEngine.isEmpty ? 'multimodal_ocr' : dominantEngine}+partial'
      : dominantEngine;

  return PlatformPdfOcrResult(
    fullText: mergedText,
    excerpt: buildExcerpt(mergedText),
    engine: resolvedEngine,
    isTruncated: anyTruncated || partial,
    pageCount: totalPages,
    processedPages: processedTotal,
    retryAttempted: retryAttempted,
    retryAttempts: retryAttempts,
    retryHintsTried: retryHints.toList(growable: false),
    partial: partial,
    retryable: partial && failedRanges.isNotEmpty,
    failedRanges: failedRanges,
    completedRanges: completedRanges,
  );
}
