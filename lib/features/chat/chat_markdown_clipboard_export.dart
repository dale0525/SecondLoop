import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'chat_markdown_rich_rendering.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

String buildChatMarkdownClipboardPlainText(
  String markdown, {
  required String emptyFallback,
}) {
  final normalized = sanitizeChatMarkdown(markdown).trim();
  if (normalized.isEmpty) {
    return emptyFallback;
  }
  return normalized;
}

String buildChatMarkdownClipboardHtml({
  required String markdown,
  required ChatMarkdownPreviewTheme theme,
  required String emptyFallback,
}) {
  final plainText = buildChatMarkdownClipboardPlainText(
    markdown,
    emptyFallback: emptyFallback,
  );
  final normalized = sanitizeChatMarkdown(markdown).trim();
  final contentHtml = normalized.isEmpty
      ? '<p>${const HtmlEscape(HtmlEscapeMode.element).convert(plainText)}</p>'
      : md.markdownToHtml(
          normalized,
          extensionSet: md.ExtensionSet.gitHubWeb,
          blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
          inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
          encodeHtml: true,
        );

  final textColor = _toCssColor(theme.textColor);
  final mutedColor = _toCssColor(theme.mutedTextColor);
  final codeBackground = _toCssColor(theme.codeBlockBackground);

  return '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
body { margin: 0; color: $textColor; font-size: 16px; line-height: 1.65; }
a { color: inherit; }
pre, code { background: $codeBackground; }
blockquote { margin: 0.4em 0; padding: 0.1em 0 0.1em 0.9em; border-left: 3px solid $mutedColor; color: $mutedColor; }
img { max-width: 100%; }
</style>
</head>
<body>
$contentHtml
</body>
</html>''';
}

String _toCssColor(Color color) {
  if (color.alpha == 255) {
    final rgb = color.value & 0x00ffffff;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  final alpha = (color.alpha / 255).toStringAsFixed(3);
  return 'rgba(${color.red}, ${color.green}, ${color.blue}, $alpha)';
}
