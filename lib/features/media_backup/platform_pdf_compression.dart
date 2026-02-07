import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'linux_pdf_compression_fallback_stub.dart'
    if (dart.library.io) 'linux_pdf_compression_fallback_io.dart'
    as linux_fallback;

const MethodChannel _channel = MethodChannel('secondloop/ocr');

typedef PdfCompressionNativeInvoke = Future<Object?> Function(
  String method,
  Map<String, Object?> arguments,
);

typedef PdfCompressionLinuxFallback = Future<Uint8List?> Function(
  Uint8List bytes, {
  required int scanDpi,
});

Future<Uint8List?> compressPdfScanPagesViaPlatform(
  Uint8List bytes, {
  required int scanDpi,
  PdfCompressionNativeInvoke? nativeInvoke,
  PdfCompressionLinuxFallback? linuxFallbackCompressor,
}) async {
  if (kIsWeb) return null;
  if (bytes.isEmpty) return null;

  final dpi = scanDpi.clamp(150, 200);
  final invoke = nativeInvoke ?? _invokeNativeMethod;
  final fallback =
      linuxFallbackCompressor ?? linux_fallback.tryCompressPdfViaLinuxFallback;

  try {
    final raw = await invoke(
      'compressPdf',
      <String, Object?>{
        'bytes': bytes,
        'scan_dpi': dpi,
      },
    );
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
  } on MissingPluginException {
    // Fall through to Linux fallback.
  } on PlatformException {
    // Fall through to Linux fallback.
  } catch (_) {
    // Fall through to Linux fallback.
  }

  try {
    return await fallback(bytes, scanDpi: dpi);
  } catch (_) {
    return null;
  }
}

Future<Object?> _invokeNativeMethod(
  String method,
  Map<String, Object?> arguments,
) {
  return _channel.invokeMethod<Object?>(method, arguments);
}
