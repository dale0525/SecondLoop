import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

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

  final orientedSize = tryReadOrientedImageSize(originalBytes);
  final resizeTarget = orientedSize == null
      ? null
      : compute1080pResizeMinDimensions(
          width: orientedSize.width,
          height: orientedSize.height,
        );
  final didResize = orientedSize != null &&
      resizeTarget != null &&
      (resizeTarget.minWidth != orientedSize.width ||
          resizeTarget.minHeight != orientedSize.height);

  if (normalized == 'image/webp' && !didResize) {
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
      minWidth: resizeTarget?.minWidth ?? 1920,
      minHeight: resizeTarget?.minHeight ?? 1080,
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
    if (!didResize && webpBytes.length >= originalBytes.length) {
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

({int width, int height})? tryReadOrientedImageSize(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) return null;

  final orientation = _tryReadJpegExifOrientation(bytes);
  if (orientation != null && _exifOrientationSwapsAxes(orientation)) {
    return (width: info.height, height: info.width);
  }

  return (width: info.width, height: info.height);
}

int? _tryReadJpegExifOrientation(Uint8List bytes) {
  try {
    if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    final exif = img.decodeJpgExif(bytes);
    final raw = exif?.imageIfd['Orientation'];
    if (raw == null) return null;
    final value = raw.toInt();
    return value >= 1 && value <= 8 ? value : null;
  } catch (_) {
    return null;
  }
}

bool _exifOrientationSwapsAxes(int orientation) =>
    orientation == 5 ||
    orientation == 6 ||
    orientation == 7 ||
    orientation == 8;

({int minWidth, int minHeight}) compute1080pResizeMinDimensions({
  required int width,
  required int height,
}) {
  final isLandscape = width >= height;
  const maxLongSide = 1920;
  const maxShortSide = 1080;

  final maxWidth = isLandscape ? maxLongSide : maxShortSide;
  final maxHeight = isLandscape ? maxShortSide : maxLongSide;

  final scale = math.max(1.0, math.max(width / maxWidth, height / maxHeight));

  final minWidth = math.max(1, (width / scale).floor());
  final minHeight = math.max(1, (height / scale).floor());
  return (minWidth: minWidth, minHeight: minHeight);
}
