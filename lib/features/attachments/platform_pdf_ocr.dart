import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'attachment_ocr_text_normalizer.dart';
import 'attachment_text_source_policy.dart';
import 'linux_onnx_ocr_fallback_stub.dart'
    if (dart.library.io) 'linux_onnx_ocr_fallback_io.dart' as linux_onnx_ocr;

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

final class _RetryOutcome {
  const _RetryOutcome({
    required this.attempted,
    required this.attemptCount,
    required this.hintsTried,
    required this.best,
  });

  final bool attempted;
  final int attemptCount;
  final List<String> hintsTried;
  final PlatformPdfOcrResult? best;
}

final class PlatformPdfOcr {
  static const MethodChannel _channel = MethodChannel('secondloop/ocr');

  // Native OCR quality on desktop can be unstable for PDFs; prefer ONNX first.
  static bool get _preferDesktopOnnxOcr {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static Future<PlatformPdfOcrResult?> tryOcrPdfBytes(
    Uint8List bytes, {
    required int maxPages,
    required int dpi,
    required String languageHints,
  }) async {
    if (kIsWeb) return null;
    if (bytes.isEmpty) return null;

    final safeMaxPages = maxPages.clamp(1, 10000);
    final safeDpi = dpi.clamp(72, 600);
    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    if (_preferDesktopOnnxOcr) {
      final modelRaw = await linux_onnx_ocr.tryOcrPdfViaLinuxOnnx(
        bytes,
        maxPages: safeMaxPages,
        dpi: safeDpi,
        languageHints: hints,
      );
      final modelParsed = _parsePayload(modelRaw);
      if (modelParsed != null) return modelParsed;
    }

    final raw = await _invokeNativeOcr(
      'ocrPdf',
      <String, Object?>{
        'bytes': bytes,
        'max_pages': safeMaxPages,
        'dpi': safeDpi,
        'language_hints': hints,
      },
    );
    final nativeParsed = _parsePayload(raw);
    if (nativeParsed != null) {
      final retryOutcome = await _retryDegradedPdfOcrIfNeeded(
        bytes: bytes,
        maxPages: safeMaxPages,
        dpi: safeDpi,
        languageHints: hints,
        baseline: nativeParsed,
      );
      final withRetryMeta = (retryOutcome.best ?? nativeParsed).copyWith(
        retryAttempted: retryOutcome.attempted,
        retryAttempts: retryOutcome.attemptCount,
        retryHintsTried: retryOutcome.hintsTried,
      );
      return withRetryMeta;
    }

    if (_preferDesktopOnnxOcr) {
      return null;
    }

    final fallbackRaw = await linux_onnx_ocr.tryOcrPdfViaLinuxOnnx(
      bytes,
      maxPages: safeMaxPages,
      dpi: safeDpi,
      languageHints: hints,
    );
    return _parsePayload(fallbackRaw);
  }

  static Future<PlatformPdfOcrResult?> tryOcrImageBytes(
    Uint8List bytes, {
    required String languageHints,
  }) async {
    if (kIsWeb) return null;
    if (bytes.isEmpty) return null;

    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    if (_preferDesktopOnnxOcr) {
      final modelRaw = await linux_onnx_ocr.tryOcrImageViaLinuxOnnx(
        bytes,
        languageHints: hints,
      );
      final modelParsed = _parsePayload(modelRaw);
      if (modelParsed != null) return modelParsed;
    }

    final raw = await _invokeNativeOcr(
      'ocrImage',
      <String, Object?>{
        'bytes': bytes,
        'language_hints': hints,
      },
    );
    final nativeParsed = _parsePayload(raw);
    if (nativeParsed != null) return nativeParsed;

    if (_preferDesktopOnnxOcr) {
      return null;
    }

    final fallbackRaw = await linux_onnx_ocr.tryOcrImageViaLinuxOnnx(
      bytes,
      languageHints: hints,
    );
    return _parsePayload(fallbackRaw);
  }

  static PlatformPdfOcrResult? _parsePayload(Object? raw) {
    final payload = _payloadAsMap(raw);
    if (payload == null) return null;

    final full =
        normalizeOcrTextForDisplay(payload['ocr_text_full']?.toString() ?? '');
    var excerpt = normalizeOcrTextForDisplay(
        payload['ocr_text_excerpt']?.toString() ?? '');
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

  static Future<_RetryOutcome> _retryDegradedPdfOcrIfNeeded({
    required Uint8List bytes,
    required int maxPages,
    required int dpi,
    required String languageHints,
    required PlatformPdfOcrResult baseline,
  }) async {
    if (dpi >= 360) {
      return const _RetryOutcome(
        attempted: false,
        attemptCount: 0,
        hintsTried: <String>[],
        best: null,
      );
    }
    final baselineProbe = _qualityProbeText(baseline);
    final baselineLooksDegraded =
        baselineProbe.isEmpty || extractedTextLooksDegraded(baselineProbe);
    final allowAutoHintRetry = languageHints == 'device_plus_en' &&
        (baselineLooksDegraded || baselineProbe.isEmpty);
    if (!baselineLooksDegraded && !allowAutoHintRetry) {
      return const _RetryOutcome(
        attempted: false,
        attemptCount: 0,
        hintsTried: <String>[],
        best: null,
      );
    }

    const retryDpi = 360;
    PlatformPdfOcrResult? best;
    var bestProbe = baselineProbe;
    var bestResult = baseline;
    var improved = false;
    var attemptCount = 0;
    final hintsTried = <String>[];

    Future<void> tryCandidate({
      required String retryHints,
      required String engineSuffix,
    }) async {
      attemptCount += 1;
      hintsTried.add(retryHints);
      final retryRaw = await _invokeNativeOcr(
        'ocrPdf',
        <String, Object?>{
          'bytes': bytes,
          'max_pages': maxPages,
          'dpi': retryDpi,
          'language_hints': retryHints,
        },
      );
      final retry = _parsePayload(retryRaw);
      if (retry == null) return;
      final retryProbe = _qualityProbeText(retry);
      if (retryProbe.isEmpty) return;
      if (!_shouldUseRetryResult(
        baseline: bestResult,
        baselineProbe: bestProbe,
        retry: retry,
        retryProbe: retryProbe,
      )) {
        return;
      }
      best = PlatformPdfOcrResult(
        fullText: retry.fullText,
        excerpt: retry.excerpt,
        engine: '${retry.engine}+$engineSuffix',
        isTruncated: retry.isTruncated,
        pageCount: retry.pageCount,
        processedPages: retry.processedPages,
      );
      bestResult = best!;
      bestProbe = _qualityProbeText(bestResult);
      improved = true;
    }

    if (baselineLooksDegraded) {
      await tryCandidate(
        retryHints: languageHints,
        engineSuffix: 'dpi$retryDpi',
      );
    }

    if (allowAutoHintRetry) {
      final latestProbe = _qualityProbeText(bestResult);
      final stillNeedsLanguageRetry =
          latestProbe.isEmpty || extractedTextLooksDegraded(latestProbe);
      if (stillNeedsLanguageRetry) {
        final preferredAutoHint = _preferredAutoRetryHint(latestProbe);
        if (!hintsTried.contains(preferredAutoHint)) {
          await tryCandidate(
            retryHints: preferredAutoHint,
            engineSuffix: 'dpi$retryDpi+$preferredAutoHint',
          );
        }
      }
    }

    return _RetryOutcome(
      attempted: attemptCount > 0,
      attemptCount: attemptCount,
      hintsTried: hintsTried,
      best: improved ? best : null,
    );
  }

  static String _qualityProbeText(PlatformPdfOcrResult value) {
    final excerpt = value.excerpt.trim();
    if (excerpt.isNotEmpty) return excerpt;
    return value.fullText.trim();
  }

  static bool _shouldUseRetryResult({
    required PlatformPdfOcrResult baseline,
    required String baselineProbe,
    required PlatformPdfOcrResult retry,
    required String retryProbe,
  }) {
    if (baselineProbe.trim().isEmpty && retryProbe.trim().isNotEmpty) {
      return true;
    }
    final baselineLooksDegraded = extractedTextLooksDegraded(baselineProbe);
    final retryLooksDegraded = extractedTextLooksDegraded(retryProbe);
    if (!baselineLooksDegraded && retryLooksDegraded) {
      return false;
    }
    final baselineScore = _qualityScore(
      baselineProbe,
      processedPages: baseline.processedPages,
      looksDegraded: baselineLooksDegraded,
    );
    final retryScore = _qualityScore(
      retryProbe,
      processedPages: retry.processedPages,
      looksDegraded: retryLooksDegraded,
    );
    if (retryScore <= baselineScore + 120) return false;
    if (retry.processedPages < baseline.processedPages &&
        retryProbe.runes.length <= baselineProbe.runes.length) {
      return false;
    }
    return true;
  }

  static int _qualityScore(
    String text, {
    required int processedPages,
    required bool looksDegraded,
  }) {
    var meaningful = 0;
    for (final rune in text.runes) {
      if (_isWhitespaceRune(rune)) continue;
      if (_isMeaningfulRune(rune)) meaningful += 1;
    }
    final totalLen = text.runes.length;
    return processedPages * 8000 +
        (looksDegraded ? 0 : 120000) +
        meaningful * 8 +
        totalLen;
  }

  static String _preferredAutoRetryHint(String text) {
    if (_looksCjkHeavy(text)) return 'zh_en';
    return 'en';
  }

  static bool _looksCjkHeavy(String text) {
    var cjk = 0;
    var latin = 0;
    for (final rune in text.runes) {
      if (_isCjkRune(rune)) {
        cjk += 1;
        continue;
      }
      if (_isAsciiAlphaNumRune(rune)) {
        latin += 1;
      }
    }
    if (cjk == 0) return false;
    return cjk >= 6 && cjk >= latin;
  }

  static bool _isWhitespaceRune(int rune) =>
      String.fromCharCode(rune).trim().isEmpty;

  static bool _isMeaningfulRune(int rune) {
    if (_isAsciiAlphaNumRune(rune)) return true;
    if (_isCjkRune(rune)) return true;
    if (rune > 127 && !_isCommonPunctuationRune(rune)) return true;
    return false;
  }

  static bool _isAsciiAlphaNumRune(int rune) {
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A);
  }

  static bool _isCjkRune(int rune) {
    return (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0xAC00 && rune <= 0xD7AF);
  }

  static bool _isCommonPunctuationRune(int rune) =>
      _commonPunctuationRunes.contains(rune);

  static final Set<int> _commonPunctuationRunes =
      '.,;:!?()[]{}<>/\\|@#%^&*_+=~`"\'-，。；：！？（）【】《》“”‘’、…·￥'.runes.toSet();

  static Future<Object?> _invokeNativeOcr(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _payloadAsMap(Object? raw) {
    if (raw is Map) {
      return raw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    if (raw is! String) return null;

    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
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
