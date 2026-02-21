import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const double _kDefaultTargetPreviewPixelWidth = 3200;
const double _kMinPreviewPixelRatio = 2.0;
const double _kMaxPreviewPixelRatio = 6.0;
const double _kMaxPreviewRasterDimension = 16000;
const int _kPaginationSearchWindowRows = 140;
const double _kPaginationMinFillRatio = 0.72;
const double _kPaginationMaxStretchRatio = 1.18;

bool shouldUsePreviewBasedPdfRender(String markdown) {
  const markmapFence = r'(^|\n)\s*```(?:markmap|mindmap)\b';
  final hasMarkmap = RegExp(markmapFence, multiLine: true).hasMatch(markdown);
  if (hasMarkmap) return true;

  final hasBlockLatex = RegExp(r'(^|\n)\s*\$\$').hasMatch(markdown);
  if (hasBlockLatex) return true;

  return RegExp(r'(?<!\\)\$(?!\$)[^\n$]+(?<!\\)\$(?!\$)').hasMatch(markdown);
}

double resolveMarkdownPreviewExportPixelRatio({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
}) {
  if (!logicalWidth.isFinite ||
      !logicalHeight.isFinite ||
      logicalWidth <= 0 ||
      logicalHeight <= 0) {
    return devicePixelRatio.clamp(1.0, _kMaxPreviewPixelRatio);
  }

  final targetRatio = _kDefaultTargetPreviewPixelWidth / logicalWidth;
  final preferredRatio = math
      .max(devicePixelRatio, targetRatio)
      .clamp(_kMinPreviewPixelRatio, _kMaxPreviewPixelRatio);

  final widthCap = _kMaxPreviewRasterDimension / logicalWidth;
  final heightCap = _kMaxPreviewRasterDimension / logicalHeight;
  final dimensionSafeCap = math.min(widthCap, heightCap);

  if (!dimensionSafeCap.isFinite || dimensionSafeCap <= 0) {
    return preferredRatio;
  }

  final boundedRatio = math.min(preferredRatio, dimensionSafeCap);
  return boundedRatio.clamp(1.0, _kMaxPreviewPixelRatio);
}

List<double> computeMarkdownPreviewPdfPageOffsets({
  required Uint8List pngBytes,
  required double sourceWidth,
  required double sourceHeight,
  required double contentWidth,
  required double contentHeight,
}) {
  if (sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      contentWidth <= 0 ||
      contentHeight <= 0) {
    return const <double>[0];
  }

  final scaledHeight = sourceHeight * (contentWidth / sourceWidth);
  final linearOffsets = _buildLinearPageOffsets(
    scaledHeight: scaledHeight,
    pageHeight: contentHeight,
  );

  final decoded = img.decodePng(pngBytes) ?? img.decodeImage(pngBytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return linearOffsets;
  }

  final pointsPerPixel = contentWidth / decoded.width;
  if (!pointsPerPixel.isFinite || pointsPerPixel <= 0) {
    return linearOffsets;
  }

  final pageHeightPx = contentHeight / pointsPerPixel;
  if (pageHeightPx <= 1) {
    return linearOffsets;
  }

  final minBreakPxGap = pageHeightPx * _kPaginationMinFillRatio;
  final maxBreakPxGap = pageHeightPx * _kPaginationMaxStretchRatio;
  final background = _estimateBackgroundColor(decoded);
  final rowScoreCache = <int, double>{};

  final offsets = <double>[0];
  var currentOffsetPx = 0.0;

  while (true) {
    final remainingPx = decoded.height - currentOffsetPx;
    if (remainingPx <= pageHeightPx + 1) {
      break;
    }

    final targetBreakPx = currentOffsetPx + pageHeightPx;
    final minBreakPx = currentOffsetPx + minBreakPxGap;
    final maxBreakPx =
        math.min(decoded.height - 1.0, currentOffsetPx + maxBreakPxGap);

    final searchStart = math
        .max(minBreakPx, targetBreakPx - _kPaginationSearchWindowRows)
        .round();
    final searchEnd = math
        .min(maxBreakPx, targetBreakPx + _kPaginationSearchWindowRows)
        .round();

    var nextBreakPx = targetBreakPx;

    if (searchEnd > searchStart) {
      var bestRow = targetBreakPx.round().clamp(searchStart, searchEnd);
      var bestScore = double.infinity;
      var bestDistance = double.infinity;

      for (var row = searchStart; row <= searchEnd; row += 1) {
        final score = rowScoreCache.putIfAbsent(
          row,
          () => _rowInkScore(decoded, row: row, background: background),
        );
        final distance = (row - targetBreakPx).abs();

        if (score < bestScore - 0.25 ||
            ((score - bestScore).abs() <= 0.25 && distance < bestDistance)) {
          bestScore = score;
          bestDistance = distance;
          bestRow = row;
        }
      }

      nextBreakPx = bestRow.toDouble();
    }

    if (nextBreakPx <= currentOffsetPx + 1) {
      nextBreakPx = math.min(targetBreakPx, decoded.height.toDouble());
    }

    if (nextBreakPx <= currentOffsetPx + 1) {
      break;
    }

    offsets.add(nextBreakPx * pointsPerPixel);
    currentOffsetPx = nextBreakPx;
  }

  return offsets;
}

List<double> _buildLinearPageOffsets({
  required double scaledHeight,
  required double pageHeight,
}) {
  if (!scaledHeight.isFinite || !pageHeight.isFinite || pageHeight <= 0) {
    return const <double>[0];
  }

  if (scaledHeight <= 0 || scaledHeight <= pageHeight) {
    return const <double>[0];
  }

  final offsets = <double>[0];
  for (var offset = pageHeight; offset < scaledHeight; offset += pageHeight) {
    offsets.add(offset);
  }
  return offsets;
}

({double r, double g, double b}) _estimateBackgroundColor(img.Image image) {
  final samples = <img.Pixel>[
    image.getPixel(0, 0),
    image.getPixel(image.width - 1, 0),
    image.getPixel(0, image.height - 1),
    image.getPixel(image.width - 1, image.height - 1),
    image.getPixel(image.width ~/ 2, 0),
    image.getPixel(image.width ~/ 2, image.height - 1),
  ];

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  for (final pixel in samples) {
    r += pixel.r.toDouble();
    g += pixel.g.toDouble();
    b += pixel.b.toDouble();
  }

  return (
    r: r / samples.length,
    g: g / samples.length,
    b: b / samples.length,
  );
}

double _rowInkScore(
  img.Image image, {
  required int row,
  required ({double r, double g, double b}) background,
}) {
  final step = math.max(1, image.width ~/ 180);
  var score = 0.0;
  var sampled = 0;

  for (var x = 0; x < image.width; x += step) {
    final pixel = image.getPixel(x, row);
    final diff = (pixel.r - background.r).abs() +
        (pixel.g - background.g).abs() +
        (pixel.b - background.b).abs();
    if (diff > 24) {
      score += diff;
    }
    sampled += 1;
  }

  if (sampled == 0) {
    return 0;
  }
  return score / sampled;
}
