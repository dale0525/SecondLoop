import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

final class ImageCompressionResult {
  const ImageCompressionResult({
    required this.bytes,
    required this.mimeType,
    required this.didCompress,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool didCompress;
}

Future<ImageCompressionResult> compressImageForStorage(
  Uint8List originalBytes, {
  required String mimeType,
  int webpQuality = 98,
}) async {
  final normalized = mimeType.trim().toLowerCase();
  if (!normalized.startsWith('image/')) {
    return ImageCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }

  if (normalized == 'image/webp') {
    return ImageCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }

  final quality = webpQuality.clamp(0, 100);

  try {
    final webp = await FlutterImageCompress.compressWithList(
      originalBytes,
      format: CompressFormat.webp,
      quality: quality,
      keepExif: true,
    );
    if (webp.isEmpty) {
      return ImageCompressionResult(
        bytes: originalBytes,
        mimeType: mimeType,
        didCompress: false,
      );
    }

    final webpBytes = Uint8List.fromList(webp);
    if (webpBytes.length >= originalBytes.length) {
      return ImageCompressionResult(
        bytes: originalBytes,
        mimeType: mimeType,
        didCompress: false,
      );
    }

    return ImageCompressionResult(
      bytes: webpBytes,
      mimeType: 'image/webp',
      didCompress: true,
    );
  } on MissingPluginException {
    return ImageCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  } catch (_) {
    return ImageCompressionResult(
      bytes: originalBytes,
      mimeType: mimeType,
      didCompress: false,
    );
  }
}
