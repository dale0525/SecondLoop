import 'package:flutter/foundation.dart';

import '../../src/rust/api/desktop_media.dart' as rust_desktop_media;
import 'attachment_ocr_text_normalizer.dart';

typedef DesktopOcrPdfInvoke = Future<dynamic> Function(
  Uint8List bytes, {
  required int maxPages,
  required int dpi,
  required String languageHints,
});

typedef DesktopOcrImageInvoke = Future<dynamic> Function(
  Uint8List bytes, {
  required String languageHints,
});

final class PlatformPdfOcrResult {
  const PlatformPdfOcrResult({
    required this.fullText,
    required this.excerpt,
    required this.engine,
    required this.isTruncated,
    required this.pageCount,
    required this.processedPages,
    this.retryAttempted = false,
    this.retryAttempts = 0,
    this.retryHintsTried = const <String>[],
  });

  final String fullText;
  final String excerpt;
  final String engine;
  final bool isTruncated;
  final int pageCount;
  final int processedPages;
  final bool retryAttempted;
  final int retryAttempts;
  final List<String> retryHintsTried;

  PlatformPdfOcrResult copyWith({
    String? fullText,
    String? excerpt,
    String? engine,
    bool? isTruncated,
    int? pageCount,
    int? processedPages,
    bool? retryAttempted,
    int? retryAttempts,
    List<String>? retryHintsTried,
  }) {
    return PlatformPdfOcrResult(
      fullText: fullText ?? this.fullText,
      excerpt: excerpt ?? this.excerpt,
      engine: engine ?? this.engine,
      isTruncated: isTruncated ?? this.isTruncated,
      pageCount: pageCount ?? this.pageCount,
      processedPages: processedPages ?? this.processedPages,
      retryAttempted: retryAttempted ?? this.retryAttempted,
      retryAttempts: retryAttempts ?? this.retryAttempts,
      retryHintsTried: retryHintsTried ?? this.retryHintsTried,
    );
  }
}

final class PlatformPdfOcr {
  static Future<PlatformPdfOcrResult?> tryOcrPdfBytes(
    Uint8List bytes, {
    required int maxPages,
    required int dpi,
    required String languageHints,
    DesktopOcrPdfInvoke? ocrPdfInvoke,
  }) async {
    if (kIsWeb || bytes.isEmpty) return null;

    final safeMaxPages = maxPages.clamp(1, 10000);
    final safeDpi = dpi.clamp(72, 600);
    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    final invoke = ocrPdfInvoke ?? _invokeDesktopOcrPdf;
    final raw = await _invokeSafely(
      () => invoke(
        bytes,
        maxPages: safeMaxPages,
        dpi: safeDpi,
        languageHints: hints,
      ),
    );
    return _parsePayload(raw);
  }

  static Future<PlatformPdfOcrResult?> tryOcrImageBytes(
    Uint8List bytes, {
    required String languageHints,
    DesktopOcrImageInvoke? ocrImageInvoke,
  }) async {
    if (kIsWeb || bytes.isEmpty) return null;

    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    final invoke = ocrImageInvoke ?? _invokeDesktopOcrImage;
    final raw = await _invokeSafely(
      () => invoke(
        bytes,
        languageHints: hints,
      ),
    );
    return _parsePayload(raw);
  }

  static Future<dynamic> _invokeDesktopOcrPdf(
    Uint8List bytes, {
    required int maxPages,
    required int dpi,
    required String languageHints,
  }) {
    return rust_desktop_media.desktopOcrPdf(
      bytes: bytes,
      maxPages: maxPages,
      dpi: dpi,
      languageHints: languageHints,
    );
  }

  static Future<dynamic> _invokeDesktopOcrImage(
    Uint8List bytes, {
    required String languageHints,
  }) {
    return rust_desktop_media.desktopOcrImage(
      bytes: bytes,
      languageHints: languageHints,
    );
  }

  static Future<dynamic> _invokeSafely(
    Future<dynamic> Function() run,
  ) async {
    try {
      return await run();
    } catch (_) {
      return null;
    }
  }

  static PlatformPdfOcrResult? _parsePayload(Object? raw) {
    final payload = _payloadAsMap(raw);
    if (payload == null) return null;

    final full =
        normalizeOcrTextForDisplay(payload['ocr_text_full']?.toString() ?? '');
    var excerpt = normalizeOcrTextForDisplay(
      payload['ocr_text_excerpt']?.toString() ?? '',
    );
    if (excerpt.isEmpty && full.isNotEmpty) {
      excerpt = full;
    }

    final engine = payload['ocr_engine']?.toString().trim() ?? '';
    final pageCount = _asInt(payload['ocr_page_count']);
    final processedPages = _asInt(payload['ocr_processed_pages']);
    final isTruncated = payload['ocr_is_truncated'] == true;

    if (engine.isEmpty || pageCount <= 0 || processedPages <= 0) {
      return null;
    }

    return PlatformPdfOcrResult(
      fullText: full,
      excerpt: excerpt,
      engine: engine,
      isTruncated: isTruncated,
      pageCount: pageCount,
      processedPages: processedPages,
    );
  }

  static Map<String, Object?>? _payloadAsMap(Object? raw) {
    if (raw == null) return null;

    if (raw is Map) {
      return raw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    try {
      final dynamic value = raw;
      return <String, Object?>{
        'ocr_text_full': value.ocrTextFull,
        'ocr_text_excerpt': value.ocrTextExcerpt,
        'ocr_engine': value.ocrEngine,
        'ocr_is_truncated': value.ocrIsTruncated,
        'ocr_page_count': value.ocrPageCount,
        'ocr_processed_pages': value.ocrProcessedPages,
      };
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }
}
