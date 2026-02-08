import 'dart:typed_data';

import 'pdf_compression.dart';

typedef PdfSmartCompressEnabledReader = Future<bool?> Function();

Future<PdfCompressionResult> compressPdfForIngest(
  Uint8List originalBytes, {
  required String mimeType,
  required PdfSmartCompressEnabledReader readPdfSmartCompressEnabled,
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

  var enabled = true;
  try {
    final value = await readPdfSmartCompressEnabled();
    if (value != null) {
      enabled = value;
    }
  } catch (_) {
    // Keep compression enabled by default when config read fails.
    enabled = true;
  }

  return compressPdfForStorage(
    originalBytes,
    mimeType: mimeType,
    config: PdfCompressionConfig(enabled: enabled),
    scanClassifier: scanClassifier,
    platformCompressor: platformCompressor,
  );
}
