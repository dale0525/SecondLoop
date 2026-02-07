import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../src/rust/db.dart';
import 'platform_pdf_compression.dart';

typedef PdfScanClassifier = bool Function(Uint8List bytes);

typedef PdfPlatformCompressor = Future<Uint8List?> Function(
  Uint8List bytes, {
  required int scanDpi,
});

final class PdfCompressionConfig {
  const PdfCompressionConfig({
    required this.enabled,
  });

  factory PdfCompressionConfig.fromContentEnrichment(
    ContentEnrichmentConfig? config,
  ) {
    return PdfCompressionConfig(
      enabled: config?.pdfSmartCompressEnabled ?? true,
    );
  }

  final bool enabled;
}

final class PdfCompressionResult {
  const PdfCompressionResult({
    required this.bytes,
    required this.mimeType,
    required this.didCompress,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool didCompress;
}

Future<PdfCompressionResult> compressPdfForStorage(
  Uint8List originalBytes, {
  required String mimeType,
  required PdfCompressionConfig config,
  PdfScanClassifier? scanClassifier,
  PdfPlatformCompressor? platformCompressor,
}) async {
  final normalizedMime = mimeType.trim().toLowerCase();
  if (normalizedMime != 'application/pdf') {
    return PdfCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }
  if (!config.enabled) {
    return PdfCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }
  if (kIsWeb || originalBytes.isEmpty) {
    return PdfCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }

  final isScanHeavy = (scanClassifier ?? _isLikelyScannedPdf)(originalBytes);
  if (!isScanHeavy) {
    // Text-heavy PDFs stay lossless by default.
    return PdfCompressionResult(
      bytes: originalBytes,
      mimeType: 'application/pdf',
      didCompress: false,
    );
  }

  final compressor = platformCompressor ?? compressPdfScanPagesViaPlatform;
  final compressed = await compressor(originalBytes, scanDpi: 180);
  if (compressed == null ||
      compressed.isEmpty ||
      compressed.length >= originalBytes.length) {
    return PdfCompressionResult(
      bytes: originalBytes,
      mimeType: 'application/pdf',
      didCompress: false,
    );
  }

  return PdfCompressionResult(
    bytes: compressed,
    mimeType: 'application/pdf',
    didCompress: true,
  );
}

bool _isLikelyScannedPdf(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sample = bytes.length <= 1024 * 1024
      ? bytes
      : Uint8List.sublistView(bytes, 0, 1024 * 1024);
  final text = utf8.decode(sample, allowMalformed: true);
  final hasImageMarker = text.contains('/Subtype /Image');
  final hasFontMarker = text.contains('/Font') || text.contains('/ToUnicode');
  if (hasImageMarker && !hasFontMarker) return true;

  // Extremely image-heavy PDFs tend to have image markers without text objects.
  if (hasImageMarker &&
      text.contains('/XObject') &&
      !text.contains('/Contents')) {
    return true;
  }
  return false;
}
