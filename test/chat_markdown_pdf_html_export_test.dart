import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_pdf_html_export.dart';
import 'package:secondloop/features/chat/chat_markdown_theme_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatMarkdownPreviewTheme buildTheme() {
    return resolveChatMarkdownTheme(
      ChatMarkdownThemePreset.paper,
      ThemeData.light(),
    );
  }

  test('PDF HTML export includes page configuration and render-ready marker',
      () async {
    final html = await buildChatMarkdownPdfHtmlDocument(
      markdown: '# Heading\n\nPlain text.',
      theme: buildTheme(),
      emptyFallback: 'Empty',
    );

    expect(html, contains('@page'));
    expect(html, contains('size: A4'));
    expect(html, contains('window.__SECONDLOOP_PDF_READY__'));
  });

  test('PDF HTML export rewrites latex nodes for KaTeX rendering', () async {
    const markdown = r'''
Inline $x^2$ and block:

$$
\begin{bmatrix}1 & 2\\3 & 4\end{bmatrix}
$$
''';
    final html = await buildChatMarkdownPdfHtmlDocument(
      markdown: markdown,
      theme: buildTheme(),
      emptyFallback: 'Empty',
    );

    expect(html, contains('class="sl-latex-inline"'));
    expect(html, contains('class="sl-latex-block"'));
    expect(html, contains('katex.render'));
  });

  test('PDF HTML export inlines local image sources when possible', () async {
    final tempDir = await Directory.systemTemp.createTemp('markdown_pdf_html');
    final imagePath = '${tempDir.path}/local.png';
    final imageBytes = <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0a,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0x00,
      0x00,
      0x03,
      0x01,
      0x01,
      0x00,
      0x18,
      0xdd,
      0x8d,
      0xb1,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ];
    await File(imagePath).writeAsBytes(imageBytes, flush: true);

    final html = await buildChatMarkdownPdfHtmlDocument(
      markdown: '![local]($imagePath)',
      theme: buildTheme(),
      emptyFallback: 'Empty',
    );

    expect(html, contains('data:image/png;base64,'));

    await tempDir.delete(recursive: true);
  });
}
