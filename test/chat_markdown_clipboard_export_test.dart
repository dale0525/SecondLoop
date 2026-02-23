import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_clipboard_export.dart';
import 'package:secondloop/features/chat/chat_markdown_theme_presets.dart';

void main() {
  test('Clipboard HTML export keeps core markdown structure', () {
    final theme = resolveChatMarkdownTheme(
      ChatMarkdownThemePreset.paper,
      ThemeData.light(),
    );

    final html = buildChatMarkdownClipboardHtml(
      markdown: '# Title\n\n- **Bold** and `code`',
      theme: theme,
      emptyFallback: 'Preview will appear as you type.',
    );

    expect(html, contains('Title</h1>'));
    expect(html, contains('<strong>Bold</strong>'));
    expect(html, contains('<code>code</code>'));
  });

  test('Clipboard plain text export falls back when markdown is empty', () {
    final text = buildChatMarkdownClipboardPlainText(
      '   ',
      emptyFallback: 'Preview will appear as you type.',
    );

    expect(text, 'Preview will appear as you type.');
  });
}
