import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_pdf_image_loader.dart';

void main() {
  test('loads image bytes from data URI payload', () async {
    final bytes = await loadMarkdownPdfImageBytes(
      'data:image/png;base64,AAECAwQ=',
    );

    expect(bytes, Uint8List.fromList(const <int>[0, 1, 2, 3, 4]));
  });

  test('returns null for invalid data URI payload', () async {
    final bytes = await loadMarkdownPdfImageBytes(
      'data:image/png;base64,***invalid***',
    );

    expect(bytes, isNull);
  });

  test('loads image bytes from local file path', () async {
    final dir = await Directory.systemTemp.createTemp('pdf-image-loader-');
    try {
      final file = File('${dir.path}/sample.bin');
      await file.writeAsBytes(const <int>[11, 22, 33, 44]);

      final bytes = await loadMarkdownPdfImageBytes(file.path);

      expect(bytes, Uint8List.fromList(const <int>[11, 22, 33, 44]));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('returns null when remote image connection fails', () async {
    final bytes = await loadMarkdownPdfImageBytes(
      'http://127.0.0.1:9/unreachable.png',
    );

    expect(bytes, isNull);
  });
}
