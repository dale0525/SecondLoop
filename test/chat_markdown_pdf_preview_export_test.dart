import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:secondloop/features/chat/chat_markdown_pdf_preview_export.dart';

void main() {
  test('Preview-based PDF render is enabled for plain markdown too', () {
    const plainMarkdown = '# Title\n\nRegular paragraph with **bold** text.';

    expect(shouldUsePreviewBasedPdfRender(plainMarkdown), isTrue);
  });

  test('Export pixel ratio scales up narrow previews for better quality', () {
    final ratio = resolveMarkdownPreviewExportPixelRatio(
      logicalWidth: 420,
      logicalHeight: 900,
      devicePixelRatio: 2,
    );

    expect(ratio, greaterThan(4.0));
  });

  test('Export pixel ratio respects raster dimension safety cap', () {
    final ratio = resolveMarkdownPreviewExportPixelRatio(
      logicalWidth: 1200,
      logicalHeight: 9000,
      devicePixelRatio: 3,
    );

    expect(ratio, lessThanOrEqualTo(2.7));
  });

  test('Export pixel ratio keeps long previews readable in PDF', () {
    final ratio = resolveMarkdownPreviewExportPixelRatio(
      logicalWidth: 960,
      logicalHeight: 7000,
      devicePixelRatio: 2,
    );

    expect(ratio, greaterThanOrEqualTo(3.3));
  });

  test('Export pixel ratio keeps very tall previews readable enough', () {
    final ratio = resolveMarkdownPreviewExportPixelRatio(
      logicalWidth: 980,
      logicalHeight: 16000,
      devicePixelRatio: 2,
    );

    expect(ratio, greaterThanOrEqualTo(1.4));
  });

  test('Preview PDF pagination avoids splitting dense formula regions', () {
    final image = img.Image(width: 120, height: 360);
    _fill(image, r: 245, g: 245, b: 245);
    _drawBlock(image, top: 20, bottom: 40);
    _drawBlock(image, top: 70, bottom: 90);
    _drawBlock(image, top: 170, bottom: 250); // dense LaTeX-like region
    _drawBlock(image, top: 300, bottom: 320);

    final offsets = computeMarkdownPreviewPdfPageOffsets(
      pngBytes: img.encodePng(image),
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 180,
    );

    expect(offsets.length, greaterThan(1));
    expect(offsets[1], isNot(inInclusiveRange(170.0, 250.0)));
  });

  test(
      'Preview PDF pagination avoids isolated low-ink rows inside dense blocks',
      () {
    final image = img.Image(width: 160, height: 520);

    _fill(image, r: 245, g: 245, b: 245);

    for (var y = 0; y < image.height; y += 1) {
      for (var x = 6; x < image.width - 6; x += 16) {
        image.setPixelRgb(x, y, 220, 220, 220);
      }
    }

    _drawBlock(image, top: 170, bottom: 250);

    for (var x = 0; x < image.width; x += 1) {
      image.setPixelRgb(x, 230, 245, 245, 245);
    }

    final offsets = computeMarkdownPreviewPdfPageOffsets(
      pngBytes: img.encodePng(image),
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 250,
    );

    expect(offsets.length, greaterThan(1));
    expect(offsets[1], greaterThanOrEqualTo(248.0));
  });

  test('Preview PDF pagination avoids splitting sparse matrix-style blocks',
      () {
    final image = img.Image(width: 180, height: 720);
    _fill(image, r: 245, g: 245, b: 245);
    _drawSparseMatrixLikeBlock(image, top: 250, bottom: 520);

    final offsets = computeMarkdownPreviewPdfPageOffsets(
      pngBytes: img.encodePng(image),
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 320,
    );

    expect(offsets.length, greaterThan(1));
    expect(offsets[1], isNot(inInclusiveRange(250.0, 520.0)));
  });

  test('Preview PDF pagination avoids splitting image-like content blocks', () {
    final image = img.Image(width: 200, height: 740);
    _fill(image, r: 245, g: 245, b: 245);
    _drawImageLikeBlock(image, top: 180, bottom: 420);

    final offsets = computeMarkdownPreviewPdfPageOffsets(
      pngBytes: img.encodePng(image),
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 260,
    );

    expect(offsets.length, greaterThan(1));
    expect(offsets[1], isNot(inInclusiveRange(180.0, 420.0)));
  });

  test('Async pagination computation keeps parity with sync result', () async {
    final image = img.Image(width: 140, height: 440);
    _fill(image, r: 245, g: 245, b: 245);
    _drawBlock(image, top: 140, bottom: 260);

    final png = img.encodePng(image);

    final syncOffsets = computeMarkdownPreviewPdfPageOffsets(
      pngBytes: png,
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 220,
    );

    final asyncOffsets = await computeMarkdownPreviewPdfPageOffsetsAsync(
      pngBytes: png,
      sourceWidth: image.width.toDouble(),
      sourceHeight: image.height.toDouble(),
      contentWidth: image.width.toDouble(),
      contentHeight: 220,
    );

    expect(asyncOffsets, syncOffsets);
  });
}

void _fill(
  img.Image image, {
  required int r,
  required int g,
  required int b,
}) {
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
}

void _drawBlock(
  img.Image image, {
  required int top,
  required int bottom,
}) {
  for (var y = top; y < bottom; y += 1) {
    for (var x = 10; x < image.width - 10; x += 1) {
      image.setPixelRgb(x, y, 20, 20, 20);
    }
  }
}

void _drawSparseMatrixLikeBlock(
  img.Image image, {
  required int top,
  required int bottom,
}) {
  for (var y = top; y < bottom; y += 1) {
    if ((y - top) % 14 > 2) {
      continue;
    }

    for (var x = 18; x < image.width - 18; x += 1) {
      image.setPixelRgb(x, y, 24, 24, 24);
    }

    image.setPixelRgb(10, y, 24, 24, 24);
    image.setPixelRgb(image.width - 11, y, 24, 24, 24);
  }
}

void _drawImageLikeBlock(
  img.Image image, {
  required int top,
  required int bottom,
}) {
  for (var y = top; y < bottom; y += 1) {
    for (var x = 8; x < image.width - 8; x += 1) {
      final value = ((x * 37 + y * 17) % 160) + 60;
      image.setPixelRgb(
        x,
        y,
        value,
        (value + 40) % 255,
        (value + 80) % 255,
      );
    }

    if ((y - top) % 29 == 0) {
      for (var x = 8; x < image.width - 8; x += 1) {
        image.setPixelRgb(x, y, 245, 245, 245);
      }
    }
  }
}
