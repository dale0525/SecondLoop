import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/desktop_media.dart' as rust_desktop_media;

typedef PdfCompressionDesktopInvoke = Future<dynamic> Function(
  Uint8List bytes, {
  required int scanDpi,
});

const MethodChannel _nativeOcrChannel = MethodChannel('secondloop/ocr');

Future<Uint8List?> compressPdfScanPagesViaPlatform(
  Uint8List bytes, {
  required int scanDpi,
  PdfCompressionDesktopInvoke? desktopCompressor,
}) async {
  if (kIsWeb || bytes.isEmpty) return null;

  final dpi = scanDpi.clamp(180, 300);
  final hasOverride = desktopCompressor != null;
  final compressor = desktopCompressor ??
      (_supportsNativePdfCompression() ? _compressViaNative : _compressViaRust);

  try {
    final raw = await compressor(bytes, scanDpi: dpi);
    final parsed = _asUint8List(raw);
    if (parsed != null) return parsed;
    if (!hasOverride && _supportsNativePdfCompression()) {
      final rustRaw = await _compressViaRust(bytes, scanDpi: dpi);
      return _asUint8List(rustRaw);
    }
  } catch (_) {
    if (!hasOverride && _supportsNativePdfCompression()) {
      try {
        final rustRaw = await _compressViaRust(bytes, scanDpi: dpi);
        return _asUint8List(rustRaw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  return null;
}

Uint8List? _asUint8List(dynamic raw) {
  if (raw == null) return null;
  if (raw is Uint8List) return raw;
  if (raw is List<int>) return Uint8List.fromList(raw);
  return null;
}

bool _supportsNativePdfCompression() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

Future<dynamic> _compressViaNative(
  Uint8List bytes, {
  required int scanDpi,
}) {
  return _nativeOcrChannel.invokeMethod<dynamic>(
    'compressPdf',
    <String, Object?>{
      'bytes': bytes,
      'scan_dpi': scanDpi,
    },
  );
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
