import 'package:flutter/foundation.dart';

import '../../src/rust/api/desktop_media.dart' as rust_desktop_media;

typedef PdfCompressionDesktopInvoke = Future<dynamic> Function(
  Uint8List bytes, {
  required int scanDpi,
});

Future<Uint8List?> compressPdfScanPagesViaPlatform(
  Uint8List bytes, {
  required int scanDpi,
  PdfCompressionDesktopInvoke? desktopCompressor,
}) async {
  if (kIsWeb || bytes.isEmpty) return null;

  final dpi = scanDpi.clamp(150, 200);
  final compressor = desktopCompressor ?? _compressViaRust;

  try {
    final raw = await compressor(bytes, scanDpi: dpi);
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
  } catch (_) {
    return null;
  }

  return null;
}

Future<dynamic> _compressViaRust(
  Uint8List bytes, {
  required int scanDpi,
}) {
  return rust_desktop_media.desktopCompressPdfScan(
    bytes: bytes,
    scanDpi: scanDpi,
  );
}
