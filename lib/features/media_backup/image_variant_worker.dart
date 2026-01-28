import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

final class ImageVariantResult {
  const ImageVariantResult({
    required this.bytes,
    required this.mimeType,
    required this.didTranscode,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool didTranscode;
}

typedef ImageVariantTranscodeFn = Future<Uint8List> Function(
  Uint8List originalBytes, {
  required int webpQuality,
});

final class ImageVariantWorker {
  static const String webpQ85 = 'webp_q85';

  static Future<ImageVariantResult> generateWebpQ85(
    Uint8List originalBytes, {
    required String mimeType,
    ImageVariantTranscodeFn? transcode,
  }) async {
    final normalized = mimeType.trim().toLowerCase();
    if (!normalized.startsWith('image/')) {
      return ImageVariantResult(
        bytes: originalBytes,
        mimeType: mimeType,
        didTranscode: false,
      );
    }

    if (normalized == 'image/webp') {
      return ImageVariantResult(
        bytes: originalBytes,
        mimeType: mimeType,
        didTranscode: false,
      );
    }

    const q = 85;

    final fn = transcode ?? _transcodeToWebp;
    Uint8List webpBytes;
    try {
      webpBytes = await fn(originalBytes, webpQuality: q);
    } catch (_) {
      webpBytes = Uint8List(0);
    }

    if (webpBytes.isEmpty || webpBytes.length >= originalBytes.length) {
      return ImageVariantResult(
        bytes: originalBytes,
        mimeType: mimeType,
        didTranscode: false,
      );
    }

    return ImageVariantResult(
      bytes: webpBytes,
      mimeType: 'image/webp',
      didTranscode: true,
    );
  }

  static Future<Uint8List> _transcodeToWebp(
    Uint8List originalBytes, {
    required int webpQuality,
  }) async {
    final clamped = webpQuality.clamp(0, 100);

    try {
      final token = ServicesBinding.rootIsolateToken;
      if (token == null) {
        final webp = await FlutterImageCompress.compressWithList(
          originalBytes,
          format: CompressFormat.webp,
          quality: clamped,
          keepExif: true,
        );
        return Uint8List.fromList(webp);
      }

      return await Isolate.run(() async {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        final webp = await FlutterImageCompress.compressWithList(
          originalBytes,
          format: CompressFormat.webp,
          quality: clamped,
          keepExif: true,
        );
        return Uint8List.fromList(webp);
      });
    } on MissingPluginException {
      return Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }
}
