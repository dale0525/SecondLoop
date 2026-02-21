import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_pdf_export_layout.dart';

void main() {
  test('Preview PDF export content uses full-bleed bounds', () {
    const pageSize = Size(595.0, 842.0);

    final bounds = buildPdfPreviewContentRect(pageSize);

    expect(bounds.left, 0);
    expect(bounds.top, 0);
    expect(bounds.width, pageSize.width);
    expect(bounds.height, pageSize.height);
  });
}
