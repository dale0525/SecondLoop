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
