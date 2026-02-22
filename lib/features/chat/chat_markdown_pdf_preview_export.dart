import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const double _kDefaultTargetPreviewPixelWidth = 4600;
const double _kMinPreviewPixelRatio = 2.0;
const double _kMaxPreviewPixelRatio = 8.0;
const double _kMaxPreviewRasterDimension = 24000;
const int _kPaginationSearchWindowRows = 220;
const int _kPaginationWhitespaceBandRadius = 3;
const double _kPaginationMinFillRatio = 0.72;
const double _kPaginationMaxStretchRatio = 1.35;
const double _kPaginationWhitespaceRowScore = 12;
const double _kPaginationWhitespaceBandScore = 18;
const double _kPaginationProtectedMinFillRatio = 0.55;
const double _kPaginationProtectedMaxStretchRatio = 1.95;
const double _kProtectedRowCoverageDiffThreshold = 10;
const double _kProtectedRowCoverageThreshold = 0.2;
const int _kProtectedRangeMaxGapRows = 12;
const int _kProtectedRangeMinHeightRows = 46;
const int _kProtectedRangePaddingRows = 2;

bool shouldUsePreviewBasedPdfRender(String markdown) {
  return true;
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

Future<List<double>> computeMarkdownPreviewPdfPageOffsetsAsync({
  required Uint8List pngBytes,
  required double sourceWidth,
  required double sourceHeight,
  required double contentWidth,
  required double contentHeight,
}) {
  final payload = <String, Object>{
    'pngBytes': pngBytes,
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
    'contentWidth': contentWidth,
    'contentHeight': contentHeight,
  };

  return compute(
    _computeMarkdownPreviewPdfPageOffsetsWorker,
    payload,
    debugLabel: 'compute-markdown-preview-pdf-page-offsets',
  );
}

List<double> _computeMarkdownPreviewPdfPageOffsetsWorker(
  Map<String, Object> payload,
) {
  return computeMarkdownPreviewPdfPageOffsets(
    pngBytes: payload['pngBytes']! as Uint8List,
    sourceWidth: payload['sourceWidth']! as double,
    sourceHeight: payload['sourceHeight']! as double,
    contentWidth: payload['contentWidth']! as double,
    contentHeight: payload['contentHeight']! as double,
  );
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

  final protectedRanges = _detectProtectedRowRanges(
    decoded,
    background: background,
  );

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
      final bandScoreCache = <int, double>{};
      final whitespaceCandidates = <({
        int row,
        double rowScore,
        double bandScore,
        double distance,
      })>[];

      var bestFallbackBandScore = double.infinity;
      var bestFallbackRowScore = double.infinity;
      var bestFallbackDistance = double.infinity;
      int? bestFallbackRow;

      for (var row = searchStart; row <= searchEnd; row += 1) {
        if (_isRowProtected(row, protectedRanges)) {
          continue;
        }

        final rowScore = rowScoreCache.putIfAbsent(
          row,
          () => _rowInkScore(decoded, row: row, background: background),
        );
        final bandScore = bandScoreCache.putIfAbsent(
          row,
          () => _rowBandInkScore(
            decoded,
            row: row,
            background: background,
            radius: _kPaginationWhitespaceBandRadius,
            rowScoreCache: rowScoreCache,
          ),
        );
        final distance = (row - targetBreakPx).abs();

        final isWhitespaceCandidate =
            rowScore <= _kPaginationWhitespaceRowScore &&
                bandScore <= _kPaginationWhitespaceBandScore;
        if (isWhitespaceCandidate) {
          whitespaceCandidates.add((
            row: row,
            rowScore: rowScore,
            bandScore: bandScore,
            distance: distance,
          ));
          continue;
        }

        if (bandScore < bestFallbackBandScore - 0.2 ||
            ((bandScore - bestFallbackBandScore).abs() <= 0.2 &&
                rowScore < bestFallbackRowScore - 0.2) ||
            ((bandScore - bestFallbackBandScore).abs() <= 0.2 &&
                (rowScore - bestFallbackRowScore).abs() <= 0.2 &&
                distance < bestFallbackDistance)) {
          bestFallbackBandScore = bandScore;
          bestFallbackRowScore = rowScore;
          bestFallbackDistance = distance;
          bestFallbackRow = row;
        }
      }

      if (whitespaceCandidates.isNotEmpty) {
        whitespaceCandidates.sort((a, b) {
          final distanceCompare = a.distance.compareTo(b.distance);
          if (distanceCompare != 0) {
            return distanceCompare;
          }

          final bandCompare = a.bandScore.compareTo(b.bandScore);
          if (bandCompare != 0) {
            return bandCompare;
          }

          return a.rowScore.compareTo(b.rowScore);
        });
        nextBreakPx = whitespaceCandidates.first.row.toDouble();
      } else if (bestFallbackRow != null) {
        nextBreakPx = bestFallbackRow.toDouble();
      } else {
        nextBreakPx = maxBreakPx;
      }

      nextBreakPx = _snapBreakOutOfProtectedRanges(
        row: nextBreakPx.round(),
        minRow: searchStart,
        maxRow: searchEnd,
        targetRow: targetBreakPx.round(),
        image: decoded,
        background: background,
        protectedRanges: protectedRanges,
        rowScoreCache: rowScoreCache,
      ).toDouble();

      if (_isRowProtected(nextBreakPx.round(), protectedRanges)) {
        final overflowBreak = _resolveOverflowProtectedBreak(
          row: nextBreakPx.round(),
          currentOffsetPx: currentOffsetPx,
          pageHeightPx: pageHeightPx,
          targetRow: targetBreakPx.round(),
          imageHeight: decoded.height,
          protectedRanges: protectedRanges,
        );
        if (overflowBreak != null) {
          nextBreakPx = overflowBreak.toDouble();
        }
      }
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

List<({int start, int end})> _detectProtectedRowRanges(
  img.Image image, {
  required ({double r, double g, double b}) background,
}) {
  if (image.height <= 0) {
    return const <({int start, int end})>[];
  }

  final activeRows = List<bool>.filled(image.height, false);
  for (var row = 0; row < image.height; row += 1) {
    final coverage = _rowInkCoverage(
      image,
      row: row,
      background: background,
      diffThreshold: _kProtectedRowCoverageDiffThreshold,
    );
    activeRows[row] = coverage >= _kProtectedRowCoverageThreshold;
  }

  final ranges = <({int start, int end})>[];
  var row = 0;
  while (row < image.height) {
    if (!activeRows[row]) {
      row += 1;
      continue;
    }

    final start = row;
    var end = row;
    var gap = 0;
    row += 1;

    while (row < image.height) {
      if (activeRows[row]) {
        end = row;
        gap = 0;
        row += 1;
        continue;
      }

      gap += 1;
      if (gap > _kProtectedRangeMaxGapRows) {
        break;
      }
      row += 1;
    }

    if (end - start + 1 < _kProtectedRangeMinHeightRows) {
      continue;
    }

    final paddedStart = math.max(0, start - _kProtectedRangePaddingRows);
    final paddedEnd =
        math.min(image.height - 1, end + _kProtectedRangePaddingRows);

    if (ranges.isNotEmpty && paddedStart <= ranges.last.end + 1) {
      final merged = (
        start: ranges.last.start,
        end: math.max(ranges.last.end, paddedEnd),
      );
      ranges[ranges.length - 1] = merged;
      continue;
    }

    ranges.add((start: paddedStart, end: paddedEnd));
  }

  return ranges;
}

int _snapBreakOutOfProtectedRanges({
  required int row,
  required int minRow,
  required int maxRow,
  required int targetRow,
  required img.Image image,
  required ({double r, double g, double b}) background,
  required List<({int start, int end})> protectedRanges,
  required Map<int, double> rowScoreCache,
}) {
  if (protectedRanges.isEmpty) {
    return row.clamp(minRow, maxRow);
  }

  final clampedRow = row.clamp(minRow, maxRow);
  if (!_isRowProtected(clampedRow, protectedRanges)) {
    return clampedRow;
  }

  final before = _findNearestSafeRowBefore(
    startRow: clampedRow,
    minRow: minRow,
    protectedRanges: protectedRanges,
  );
  final after = _findNearestSafeRowAfter(
    startRow: clampedRow,
    maxRow: maxRow,
    protectedRanges: protectedRanges,
  );

  if (before == null && after == null) {
    return clampedRow;
  }
  if (before == null) {
    return after!;
  }
  if (after == null) {
    return before;
  }

  final beforeBandScore = _rowBandInkScore(
    image,
    row: before,
    background: background,
    radius: _kPaginationWhitespaceBandRadius,
    rowScoreCache: rowScoreCache,
  );
  final afterBandScore = _rowBandInkScore(
    image,
    row: after,
    background: background,
    radius: _kPaginationWhitespaceBandRadius,
    rowScoreCache: rowScoreCache,
  );

  final beforeDistance = (targetRow - before).abs();
  final afterDistance = (after - targetRow).abs();

  final beforePriority = beforeBandScore * 4 + beforeDistance;
  final afterPriority = afterBandScore * 4 + afterDistance;

  if (beforePriority <= afterPriority) {
    return before;
  }
  return after;
}

int? _findNearestSafeRowBefore({
  required int startRow,
  required int minRow,
  required List<({int start, int end})> protectedRanges,
}) {
  var cursor = startRow;
  while (cursor >= minRow) {
    final range = _protectedRangeContainingRow(cursor, protectedRanges);
    if (range == null) {
      return cursor;
    }
    cursor = range.start - 1;
  }
  return null;
}

int? _resolveOverflowProtectedBreak({
  required int row,
  required double currentOffsetPx,
  required double pageHeightPx,
  required int targetRow,
  required int imageHeight,
  required List<({int start, int end})> protectedRanges,
}) {
  if (!_isRowProtected(row, protectedRanges)) {
    return row;
  }

  final before = _findNearestSafeRowBefore(
    startRow: row,
    minRow: 0,
    protectedRanges: protectedRanges,
  );
  final after = _findNearestSafeRowAfter(
    startRow: row,
    maxRow: imageHeight - 1,
    protectedRanges: protectedRanges,
  );

  final hardMinBreak =
      (currentOffsetPx + pageHeightPx * _kPaginationProtectedMinFillRatio)
          .round();
  final hardMaxBreak =
      (currentOffsetPx + pageHeightPx * _kPaginationProtectedMaxStretchRatio)
          .round();

  final beforeAllowed =
      before != null && before > currentOffsetPx + 1 && before >= hardMinBreak;
  final afterAllowed = after != null && after <= hardMaxBreak;

  if (beforeAllowed && afterAllowed) {
    final beforeDistance = (targetRow - before).abs();
    final afterDistance = (after - targetRow).abs();
    return beforeDistance <= afterDistance ? before : after;
  }
  if (afterAllowed) {
    return after;
  }
  if (beforeAllowed) {
    return before;
  }

  if (before == null && after == null) {
    return null;
  }
  if (before == null) {
    return after;
  }
  if (after == null) {
    return before;
  }

  final beforeDistance = (targetRow - before).abs();
  final afterDistance = (after - targetRow).abs();
  return beforeDistance <= afterDistance ? before : after;
}

int? _findNearestSafeRowAfter({
  required int startRow,
  required int maxRow,
  required List<({int start, int end})> protectedRanges,
}) {
  var cursor = startRow;
  while (cursor <= maxRow) {
    final range = _protectedRangeContainingRow(cursor, protectedRanges);
    if (range == null) {
      return cursor;
    }
    cursor = range.end + 1;
  }
  return null;
}

({int start, int end})? _protectedRangeContainingRow(
  int row,
  List<({int start, int end})> protectedRanges,
) {
  for (final range in protectedRanges) {
    if (row < range.start) {
      return null;
    }
    if (row <= range.end) {
      return range;
    }
  }
  return null;
}

bool _isRowProtected(int row, List<({int start, int end})> protectedRanges) {
  return _protectedRangeContainingRow(row, protectedRanges) != null;
}

double _rowBandInkScore(
  img.Image image, {
  required int row,
  required ({double r, double g, double b}) background,
  required int radius,
  required Map<int, double> rowScoreCache,
}) {
  final start = math.max(0, row - radius);
  final end = math.min(image.height - 1, row + radius);
  if (start > end) {
    return 0;
  }

  var sum = 0.0;
  var count = 0;
  for (var cursor = start; cursor <= end; cursor += 1) {
    final score = rowScoreCache.putIfAbsent(
      cursor,
      () => _rowInkScore(image, row: cursor, background: background),
    );
    sum += score;
    count += 1;
  }

  if (count == 0) {
    return 0;
  }
  return sum / count;
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

double _rowInkCoverage(
  img.Image image, {
  required int row,
  required ({double r, double g, double b}) background,
  required double diffThreshold,
}) {
  final step = math.max(1, image.width ~/ 240);
  var covered = 0;
  var sampled = 0;

  for (var x = 0; x < image.width; x += step) {
    final pixel = image.getPixel(x, row);
    final diff = (pixel.r - background.r).abs() +
        (pixel.g - background.g).abs() +
        (pixel.b - background.b).abs();
    if (diff > diffThreshold) {
      covered += 1;
    }
    sampled += 1;
  }

  if (sampled == 0) {
    return 0;
  }
  return covered / sampled;
}
