import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

typedef DesktopPdfCompressInvoke = Future<dynamic> Function(
  Uint8List bytes, {
  required int scanDpi,
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

final class _RuntimePdfRetryState {
  const _RuntimePdfRetryState({
    required this.parsed,
    this.rasterizedBytes,
  });

  final PlatformPdfOcrResult? parsed;
  final Uint8List? rasterizedBytes;
}

final class PlatformPdfOcr {
  static const MethodChannel _nativeOcrChannel =
      MethodChannel('secondloop/ocr');
  static const List<String> _runtimeUnavailableErrorMarkers = <String>[
    'runtime_not_initialized',
    'runtime_missing',
    'desktop_runtime_not_supported',
    'desktop_runtime_dir_unavailable',
  ];

  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static Future<PlatformPdfOcrResult?> tryOcrPdfBytes(
    Uint8List bytes, {
    required int maxPages,
    required int dpi,
    required String languageHints,
    DesktopOcrPdfInvoke? ocrPdfInvoke,
    DesktopPdfCompressInvoke? compressPdfInvoke,
  }) async {
    _lastErrorMessage = null;
    if (kIsWeb || bytes.isEmpty) {
      _lastErrorMessage = 'ocr_input_unavailable';
      return null;
    }

    final safeMaxPages = maxPages.clamp(1, 10000);
    final safeDpi = dpi.clamp(72, 600);
    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    final invoke = ocrPdfInvoke ?? _invokeDesktopOcrPdf;
    final compressInvoke = compressPdfInvoke ?? _invokeRustCompressPdfForOcr;
    final raw = await _invokeSafely(
      () => invoke(
        bytes,
        maxPages: safeMaxPages,
        dpi: safeDpi,
        languageHints: hints,
      ),
    );
    var parsed = _parsePayload(raw);
    final retryState = await _retryRuntimeWithPlatformPdfRecoveryIfNeeded(
      parsed: parsed,
      originalBytes: bytes,
      invoke: invoke,
      compressInvoke: compressInvoke,
      maxPages: safeMaxPages,
      dpi: safeDpi,
      languageHints: hints,
    );
    parsed = retryState.parsed;
    parsed = await _maybeRescueRuntimeGarbledPdfWithNativeOcr(
      parsed: parsed,
      originalBytes: bytes,
      preferredRasterizedBytes: retryState.rasterizedBytes,
      maxPages: safeMaxPages,
      dpi: safeDpi,
      languageHints: hints,
      compressInvoke: compressInvoke,
    );
    final runtimeError = _lastErrorMessage;
    final shouldFallbackToNative = _shouldFallbackToNativeOcr(
          parsed: parsed,
          runtimeError: runtimeError,
        ) ||
        _shouldPreferNativeMobilePdfOcr(
          parsed: parsed,
          runtimeError: runtimeError,
        );
    if (shouldFallbackToNative) {
      final nativeDpi = _effectiveNativePdfOcrDpi(safeDpi);
      final nativeRaw = await _invokeSafely(
        () => _invokeNativeOcrPdf(
          bytes,
          maxPages: safeMaxPages,
          dpi: nativeDpi,
          languageHints: hints,
        ),
      );
      final nativeParsed = _parsePayload(nativeRaw);
      if (nativeParsed != null &&
          (parsed == null || nativeParsed.fullText.trim().isNotEmpty)) {
        parsed = nativeParsed;
      }
    }
    if (parsed != null) {
      _lastErrorMessage = null;
      return parsed;
    }
    if (_lastErrorMessage == null) {
      _lastErrorMessage = 'ocr_payload_invalid_or_empty';
      debugPrint('PlatformPdfOcr parse failed: payload invalid_or_empty');
    }
    return null;
  }

  static Future<PlatformPdfOcrResult?> tryOcrImageBytes(
    Uint8List bytes, {
    required String languageHints,
    DesktopOcrImageInvoke? ocrImageInvoke,
  }) async {
    _lastErrorMessage = null;
    if (kIsWeb || bytes.isEmpty) {
      _lastErrorMessage = 'ocr_input_unavailable';
      return null;
    }

    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    final invoke = ocrImageInvoke ?? _invokeDesktopOcrImage;
    final raw = await _invokeSafely(
      () => invoke(
        bytes,
        languageHints: hints,
      ),
    );
    var parsed = _parsePayload(raw);
    final runtimeError = _lastErrorMessage;
    if (_shouldFallbackToNativeOcr(
        parsed: parsed, runtimeError: runtimeError)) {
      final nativeRaw = await _invokeSafely(
        () => _invokeNativeOcrImage(
          bytes,
          languageHints: hints,
        ),
      );
      final nativeParsed = _parsePayload(nativeRaw);
      if (nativeParsed != null && nativeParsed.fullText.trim().isNotEmpty) {
        parsed = nativeParsed;
      }
    }
    if (parsed != null) {
      _lastErrorMessage = null;
      return parsed;
    }
    if (_lastErrorMessage == null) {
      _lastErrorMessage = 'ocr_payload_invalid_or_empty';
      debugPrint('PlatformPdfOcr parse failed: payload invalid_or_empty');
    }
    return null;
  }

  static bool _isDesktopMacOs() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool _isDesktopWindows() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool _isDesktopLinux() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool _isMobileAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _isMobileIos() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool _isMobilePlatform() => _isMobileAndroid() || _isMobileIos();

  static bool _canUseNativeOcrFallback() =>
      _isDesktopMacOs() || _isDesktopWindows() || _isMobilePlatform();

  static bool _canUsePlatformPdfRasterizationRecovery() =>
      _isDesktopMacOs() || _isDesktopWindows() || _isDesktopLinux();

  static bool _shouldFallbackToNativeOcr({
    required PlatformPdfOcrResult? parsed,
    required String? runtimeError,
  }) {
    if (!_canUseNativeOcrFallback()) return false;
    if (parsed != null) return false;
    final message = runtimeError?.trim().toLowerCase() ?? '';
    if (message.isEmpty) return false;
    for (final marker in _runtimeUnavailableErrorMarkers) {
      if (message.contains(marker)) return true;
    }
    return false;
  }

  static bool _shouldPreferNativeMobilePdfOcr({
    required PlatformPdfOcrResult? parsed,
    required String? runtimeError,
  }) {
    if (!_isMobilePlatform()) return false;
    if (parsed == null) {
      return (runtimeError?.trim().isNotEmpty ?? false);
    }
    if (parsed.fullText.trim().isNotEmpty) return false;
    return parsed.engine.trim().toLowerCase().startsWith('desktop_rust_pdf_');
  }

  static int _effectiveNativePdfOcrDpi(int dpi) {
    if (!_isMobilePlatform()) return dpi;
    return dpi < 260 ? 260 : dpi;
  }

  static Future<_RuntimePdfRetryState>
      _retryRuntimeWithPlatformPdfRecoveryIfNeeded({
    required PlatformPdfOcrResult? parsed,
    required Uint8List originalBytes,
    required DesktopOcrPdfInvoke invoke,
    required DesktopPdfCompressInvoke compressInvoke,
    required int maxPages,
    required int dpi,
    required String languageHints,
  }) async {
    if (!_canUsePlatformPdfRasterizationRecovery()) {
      return _RuntimePdfRetryState(parsed: parsed);
    }
    if (parsed == null) return const _RuntimePdfRetryState(parsed: null);
    if (parsed.engine != 'desktop_rust_pdf_image_decode_empty') {
      return _RuntimePdfRetryState(parsed: parsed);
    }
    if (parsed.fullText.trim().isNotEmpty) {
      return _RuntimePdfRetryState(parsed: parsed);
    }

    final compressedBytes = await _invokePlatformPdfRecoveryBytes(
      originalBytes,
      dpi: dpi,
      compressInvoke: compressInvoke,
    );
    if (compressedBytes == null || compressedBytes.isEmpty) {
      return _RuntimePdfRetryState(parsed: parsed);
    }
    if (listEquals(compressedBytes, originalBytes)) {
      return _RuntimePdfRetryState(parsed: parsed);
    }

    final retryRaw = await _invokeSafely(
      () => invoke(
        compressedBytes,
        maxPages: maxPages,
        dpi: dpi,
        languageHints: languageHints,
      ),
    );
    final retryParsed = _parsePayload(retryRaw);
    if (retryParsed == null) {
      return _RuntimePdfRetryState(
        parsed: parsed,
        rasterizedBytes: compressedBytes,
      );
    }

    if (retryParsed.fullText.trim().isNotEmpty ||
        retryParsed.engine != parsed.engine) {
      return _RuntimePdfRetryState(
        parsed: retryParsed.copyWith(
          retryAttempted: true,
          retryAttempts: (parsed.retryAttempts + 1).clamp(1, 99),
          retryHintsTried: <String>[languageHints],
        ),
        rasterizedBytes: compressedBytes,
      );
    }

    return _RuntimePdfRetryState(
      parsed: parsed.copyWith(
        retryAttempted: true,
        retryAttempts: (parsed.retryAttempts + 1).clamp(1, 99),
        retryHintsTried: <String>[languageHints],
      ),
      rasterizedBytes: compressedBytes,
    );
  }

  static Future<Uint8List?> _invokePlatformPdfRecoveryBytes(
    Uint8List originalBytes, {
    required int dpi,
    required DesktopPdfCompressInvoke compressInvoke,
  }) async {
    if (_isDesktopMacOs() || _isDesktopWindows()) {
      final recoveryDpi = dpi < 300 ? 300 : dpi;
      final raw = await _invokeSafely(
        () => _invokePlatformRasterizePdfForOcr(
          originalBytes,
          scanDpi: recoveryDpi,
        ),
      );
      return _asUint8List(raw);
    }
    if (_isDesktopLinux()) {
      final compressDpi = dpi.clamp(180, 300);
      final raw = await _invokeSafely(
        () => compressInvoke(
          originalBytes,
          scanDpi: compressDpi,
        ),
      );
      return _asUint8List(raw);
    }
    return null;
  }

  static Future<PlatformPdfOcrResult?>
      _maybeRescueRuntimeGarbledPdfWithNativeOcr({
    required PlatformPdfOcrResult? parsed,
    required Uint8List originalBytes,
    Uint8List? preferredRasterizedBytes,
    required int maxPages,
    required int dpi,
    required String languageHints,
    required DesktopPdfCompressInvoke compressInvoke,
  }) async {
    if (!_shouldAttemptNativeQualityRescue(parsed)) return parsed;

    final rescueDpi = dpi < 300 ? 300 : dpi;
    final rasterizedBytes =
        preferredRasterizedBytes != null && preferredRasterizedBytes.isNotEmpty
            ? preferredRasterizedBytes
            : await _invokePlatformPdfRecoveryBytes(
                originalBytes,
                dpi: rescueDpi,
                compressInvoke: compressInvoke,
              );
    if (rasterizedBytes == null || rasterizedBytes.isEmpty) {
      return parsed;
    }

    final nativeRaw = await _invokeSafely(
      () => _invokeNativeOcrPdf(
        rasterizedBytes,
        maxPages: maxPages,
        dpi: rescueDpi,
        languageHints: languageHints,
      ),
    );
    final nativeParsed = _parsePayload(nativeRaw);
    if (!_shouldUseNativeOcrRescue(
        nativeParsed: nativeParsed, runtimeParsed: parsed)) {
      return parsed;
    }

    final previousAttempts = parsed?.retryAttempts ?? 0;
    final nextAttempts = (previousAttempts + 1).clamp(1, 99);
    final mergedHints = _mergeRetryHints(
      parsed?.retryHintsTried ?? const <String>[],
      languageHints,
    );
    return nativeParsed!.copyWith(
      retryAttempted: true,
      retryAttempts: nextAttempts,
      retryHintsTried: mergedHints,
    );
  }

  static bool _shouldAttemptNativeQualityRescue(
    PlatformPdfOcrResult? parsed,
  ) {
    if (!_canUseNativeOcrFallback()) return false;
    if (parsed == null) return false;
    if (!parsed.retryAttempted) return false;
    if (parsed.engine != 'desktop_rust_pdf_onnx') return false;
    final full = parsed.fullText.trim();
    if (full.isEmpty) return false;
    if (_countNonSpaceRunes(full) < 80) return false;
    if (_looksLikeRuntimeGarbledText(full)) return true;
    return _ocrTextQualityScore(full) < 12.0;
  }

  static bool _shouldUseNativeOcrRescue({
    required PlatformPdfOcrResult? nativeParsed,
    required PlatformPdfOcrResult? runtimeParsed,
  }) {
    if (nativeParsed == null) return false;
    if (runtimeParsed == null) return nativeParsed.fullText.trim().isNotEmpty;
    final nativeText = nativeParsed.fullText.trim();
    final runtimeText = runtimeParsed.fullText.trim();
    if (nativeText.isEmpty) return false;
    if (runtimeText.isEmpty) return true;

    final runtimeScore = _ocrTextQualityScore(runtimeText);
    final nativeScore = _ocrTextQualityScore(nativeText);
    if (nativeScore > runtimeScore * 1.15) return true;
    return _countNonSpaceRunes(nativeText) >
        (_countNonSpaceRunes(runtimeText) + 80);
  }

  static bool _looksLikeRuntimeGarbledText(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 10) return false;

    var suspiciousLines = 0;
    for (final line in lines) {
      final nonSpace = _countNonSpaceRunes(line);
      if (nonSpace <= 3) {
        suspiciousLines += 1;
        continue;
      }
      if (nonSpace <= 8 && _hasCjkRune(line) && _hasAsciiAlphaNumRune(line)) {
        suspiciousLines += 1;
      }
    }

    final suspiciousRatio = suspiciousLines / lines.length;
    if (suspiciousRatio >= 0.45) {
      return true;
    }
    return _ocrTextQualityScore(text) < 10.0;
  }

  static double _ocrTextQualityScore(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return 0.0;

    var nonSpace = 0;
    var readable = 0;
    var shortLines = 0;
    var longLines = 0;

    for (final line in lines) {
      var lineNonSpace = 0;
      for (final rune in line.runes) {
        if (_isWhitespaceRune(rune)) continue;
        lineNonSpace += 1;
        nonSpace += 1;
        if (_isReadableRune(rune)) {
          readable += 1;
        }
      }
      if (lineNonSpace <= 3) {
        shortLines += 1;
      }
      if (lineNonSpace >= 8) {
        longLines += 1;
      }
    }

    if (nonSpace == 0) return 0.0;

    final readableRatio = readable / nonSpace;
    final shortRatio = shortLines / lines.length;
    final longRatio = longLines / lines.length;
    final density = math.sqrt(nonSpace.toDouble());
    return density *
        readableRatio *
        (1.0 - shortRatio * 0.75) *
        (0.8 + longRatio * 0.4);
  }

  static bool _hasAsciiAlphaNumRune(String text) {
    for (final rune in text.runes) {
      if (_isAsciiAlphaNumRune(rune)) return true;
    }
    return false;
  }

  static bool _hasCjkRune(String text) {
    for (final rune in text.runes) {
      if (_isCjkRune(rune)) return true;
    }
    return false;
  }

  static int _countNonSpaceRunes(String text) {
    var count = 0;
    for (final rune in text.runes) {
      if (_isWhitespaceRune(rune)) continue;
      count += 1;
    }
    return count;
  }

  static bool _isReadableRune(int rune) =>
      _isAsciiAlphaNumRune(rune) || _isCjkRune(rune);

  static bool _isAsciiAlphaNumRune(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);

  static bool _isCjkRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);

  static bool _isWhitespaceRune(int rune) =>
      rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0B ||
      rune == 0x0C ||
      rune == 0x0D ||
      rune == 0x3000;

  static List<String> _mergeRetryHints(
    List<String> current,
    String next,
  ) {
    final out = <String>[];
    for (final hint in current) {
      final value = hint.trim();
      if (value.isEmpty || out.contains(value)) continue;
      out.add(value);
    }
    final normalized = next.trim();
    if (normalized.isNotEmpty && !out.contains(normalized)) {
      out.add(normalized);
    }
    return out;
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

  static Future<dynamic> _invokeNativeOcrPdf(
    Uint8List bytes, {
    required int maxPages,
    required int dpi,
    required String languageHints,
  }) {
    return _nativeOcrChannel.invokeMethod<dynamic>(
      'ocrPdf',
      <String, Object?>{
        'bytes': bytes,
        'max_pages': maxPages,
        'dpi': dpi,
        'language_hints': languageHints,
      },
    );
  }

  static Future<dynamic> _invokeNativeOcrImage(
    Uint8List bytes, {
    required String languageHints,
  }) {
    return _nativeOcrChannel.invokeMethod<dynamic>(
      'ocrImage',
      <String, Object?>{
        'bytes': bytes,
        'language_hints': languageHints,
      },
    );
  }

  static Future<dynamic> _invokePlatformRasterizePdfForOcr(
    Uint8List bytes, {
    required int scanDpi,
  }) {
    return _nativeOcrChannel.invokeMethod<dynamic>(
      'rasterizePdfForOcr',
      <String, Object?>{
        'bytes': bytes,
        'scan_dpi': scanDpi,
      },
    );
  }

  static Future<dynamic> _invokeRustCompressPdfForOcr(
    Uint8List bytes, {
    required int scanDpi,
  }) {
    return rust_desktop_media.desktopCompressPdfScan(
      bytes: bytes,
      scanDpi: scanDpi,
    );
  }

  static Future<dynamic> _invokeSafely(
    Future<dynamic> Function() run,
  ) async {
    try {
      return await run();
    } catch (error, stackTrace) {
      _lastErrorMessage = '$error';
      debugPrint('PlatformPdfOcr invoke failed: $error');
      debugPrint('$stackTrace');
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

  static Uint8List? _asUint8List(Object? raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is ByteData) {
      return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    }
    return null;
  }
}
