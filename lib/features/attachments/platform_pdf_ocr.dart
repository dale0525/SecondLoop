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
    final raw = await _invokeSafely(
      () => invoke(
        bytes,
        maxPages: safeMaxPages,
        dpi: safeDpi,
        languageHints: hints,
      ),
    );
    var parsed = _parsePayload(raw);
    final runtimeError = _lastErrorMessage;
    final shouldFallbackToNative = _shouldFallbackToNativeOcr(
          parsed: parsed,
          runtimeError: runtimeError,
        ) ||
        _shouldPreferNativeMobilePdfOcr(
          parsed: parsed,
          runtimeError: runtimeError,
        ) ||
        _shouldPreferNativeDesktopPdfOcrOnEmptyRuntimeResult(
          parsed: parsed,
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

  static bool _isMobileAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _isMobileIos() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool _isMobilePlatform() => _isMobileAndroid() || _isMobileIos();

  static bool _canUseNativeOcrFallback() =>
      _isDesktopMacOs() || _isDesktopWindows() || _isMobilePlatform();

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

  static bool _shouldPreferNativeDesktopPdfOcrOnEmptyRuntimeResult({
    required PlatformPdfOcrResult? parsed,
  }) {
    if (!_isDesktopMacOs() && !_isDesktopWindows()) return false;
    if (parsed == null) return false;
    if (parsed.fullText.trim().isNotEmpty) return false;
    return parsed.engine.trim().toLowerCase().startsWith('desktop_rust_pdf_');
  }

  static int _effectiveNativePdfOcrDpi(int dpi) {
    if (!_isMobilePlatform()) return dpi;
    return dpi < 260 ? 260 : dpi;
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
}
