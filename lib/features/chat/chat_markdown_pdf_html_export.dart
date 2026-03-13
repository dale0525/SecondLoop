import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'chat_markdown_rich_rendering.dart';
import 'chat_markdown_pdf_katex_assets.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_export_image_sources.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

final RegExp _kHtmlLatexInlineTagPattern = RegExp(
  r'<latex-inline\b([^>]*)>(?:\s*</latex-inline>)?',
  caseSensitive: false,
);
final RegExp _kHtmlLatexBlockTagPattern = RegExp(
  r'<latex-block\b([^>]*)>(?:\s*</latex-block>)?',
  caseSensitive: false,
);
final RegExp _kHtmlMarkmapTagPattern = RegExp(
  r'<markmap\b([^>]*)>(?:\s*</markmap>)?',
  caseSensitive: false,
);

Future<String> buildChatMarkdownPdfHtmlDocument({
  required String markdown,
  required ChatMarkdownPreviewTheme theme,
  required String emptyFallback,
  List<AttachmentDraftPayload> draftAttachments =
      const <AttachmentDraftPayload>[],
  Future<ChatMarkdownExportImageData?> Function(String attachmentSha256)?
      readPersistedAttachment,
}) async {
  final normalized = sanitizeChatMarkdown(markdown).trim();
  final hydratedMarkdown = await inlineMarkdownImageSourcesAsDataUrls(
    normalized.isEmpty ? markdown : normalized,
    draftAttachments: draftAttachments,
    readPersistedAttachment: readPersistedAttachment,
  );
  final plainText = normalized.isEmpty ? emptyFallback : normalized;
  final fallbackHtml =
      const HtmlEscape(HtmlEscapeMode.element).convert(plainText);
  final contentHtml = normalized.isEmpty
      ? '<p>$fallbackHtml</p>'
      : md.markdownToHtml(
          hydratedMarkdown,
          extensionSet: md.ExtensionSet.gitHubWeb,
          blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
          inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
          encodeHtml: true,
        );

  final transformedHtml = _transformRichTagHtml(contentHtml);

  final katexAssets = await loadBundledKatexAssets();

  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
${katexAssets.css}
</style>
<style>
@page {
  size: A4;
  margin: 48pt 54pt 64pt 54pt;
  background: ${_toCssColor(theme.panelColor)};
}
:root {
  color-scheme: only light;
}
* {
  box-sizing: border-box;
}
html,
body {
  margin: 0;
  padding: 0;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
html {
  background: ${_toCssColor(theme.panelColor)};
}
@media print {
  * {
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}
body {
  position: relative;
  z-index: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Helvetica Neue", Arial, "Noto Sans", sans-serif;
  font-size: 13px;
  line-height: 1.45;
  color: ${_toCssColor(theme.textColor)};
  background: ${_toCssColor(theme.panelColor)};
  word-break: break-word;
  overflow-wrap: anywhere;
}
body::before {
  content: "";
  position: fixed;
  inset: 0;
  background: ${_toCssColor(theme.panelColor)};
  z-index: -1;
  pointer-events: none;
}
a {
  color: ${_toCssColor(theme.linkColor)};
  text-decoration: underline;
}
p,
ul,
ol {
  margin: 0 0 0.8em;
}
li > p {
  margin-bottom: 0.42em;
}
h1,
h2,
h3,
h4,
h5,
h6 {
  margin: 1.1em 0 0.5em;
  color: ${_toCssColor(theme.textColor)};
  break-after: avoid-page;
  page-break-after: avoid;
}
h1 {
  font-size: 21px;
  line-height: 1.3;
}
h2 {
  font-size: 18px;
}
h3 {
  font-size: 16px;
}
pre,
code {
  font-family: Menlo, Monaco, Consolas, "Courier New", monospace;
}
code {
  font-size: 0.93em;
  color: ${_toCssColor(theme.inlineCodeForeground)};
  background: ${_toCssColor(theme.inlineCodeBackground)};
  border-radius: 5px;
  padding: 0.09em 0.34em;
}
pre {
  margin: 0.76em 0 1em;
  padding: 10px;
  font-size: 12px;
  line-height: 1.45;
  color: ${_toCssColor(theme.inlineCodeForeground)};
  background: ${_toCssColor(theme.codeBlockBackground)};
  border: 1px solid ${_toCssColor(theme.borderColor)};
  border-radius: 10px;
  overflow-x: auto;
  break-inside: avoid-page;
  page-break-inside: avoid;
}
pre code {
  padding: 0;
  background: transparent;
  border-radius: 0;
}
blockquote {
  margin: 0.72em 0;
  padding: 8px 10px;
  color: ${_toCssColor(theme.mutedTextColor)};
  background: ${_toCssColor(theme.quoteBackground)};
  border-left: 3px solid ${_toCssColor(theme.quoteBorder)};
  border-radius: 10px;
  break-inside: avoid-page;
  page-break-inside: avoid;
}
hr {
  border: 0;
  border-top: 1px solid ${_toCssColor(theme.dividerColor)};
  margin: 1em 0;
}
table {
  width: 100%;
  border-collapse: collapse;
  margin: 0.8em 0;
  break-inside: avoid-page;
  page-break-inside: avoid;
}
th,
td {
  border: 1px solid ${_toCssColor(theme.borderColor)};
  padding: 6px 8px;
  vertical-align: top;
}
img,
svg,
video,
.sl-latex-block,
.sl-latex-inline-matrix,
.katex-display,
.katex-display > .katex,
.sl-markmap-fallback {
  break-inside: avoid-page;
  page-break-inside: avoid;
  -webkit-column-break-inside: avoid;
}
img {
  display: block;
  max-width: 100%;
  height: auto;
  margin: 0.75em auto;
}
.sl-latex-inline {
  display: inline-flex;
  align-items: center;
  padding: 2px 6px;
  border-radius: 6px;
  color: ${_toCssColor(theme.textColor)};
  background: ${_toCssColor(theme.inlineCodeBackground)};
}
.sl-latex-inline-matrix {
  display: block;
  margin: 0.42em 0;
  overflow-x: auto;
  break-inside: avoid-page;
  page-break-inside: avoid;
}
.sl-latex-block {
  margin: 0.75em 0;
  padding: 12px;
  border-radius: 10px;
  border: 1px solid ${_toCssColor(theme.borderColor)};
  background: ${_toCssColor(theme.codeBlockBackground)};
  overflow-x: auto;
}
.sl-latex-block .katex-display {
  margin: 0;
}
.sl-markmap-fallback {
  margin: 0.75em 0;
  padding: 10px;
  border-radius: 10px;
  border: 1px solid ${_toCssColor(theme.borderColor)};
  background: ${_toCssColor(theme.codeBlockBackground)};
  color: ${_toCssColor(theme.mutedTextColor)};
}
</style>
<script>
${katexAssets.js}
</script>
<script>
window.__SECONDLOOP_PDF_READY__ = false;
(function () {
  function normalizeLatexValue(raw) {
    if (!raw) return '';
    return raw.replace(/\u00a0/g, ' ').trim();
  }

  function renderLatexElements() {
    var katexRef = window.katex;
    if (!katexRef || typeof katexRef.render !== 'function') {
      return;
    }

    var inlineNodes = document.querySelectorAll('.sl-latex-inline[data-latex]');
    for (var i = 0; i < inlineNodes.length; i += 1) {
      var node = inlineNodes[i];
      var latex = normalizeLatexValue(node.getAttribute('data-latex'));
      if (!latex) {
        continue;
      }
      var inlineMatrix = /\\begin[{](?:matrix|pmatrix|bmatrix|Bmatrix|vmatrix|Vmatrix|smallmatrix|array)[}]/.test(latex);
      if (inlineMatrix) {
        node.classList.add('sl-latex-inline-matrix');
      }
      try {
        katexRef.render(latex, node, {
          displayMode: inlineMatrix,
          throwOnError: false,
          strict: 'ignore',
        });
      } catch (_) {
        node.textContent = latex;
      }
    }

    var blockNodes = document.querySelectorAll('.sl-latex-block[data-latex]');
    for (var j = 0; j < blockNodes.length; j += 1) {
      var block = blockNodes[j];
      var expr = normalizeLatexValue(block.getAttribute('data-latex'));
      if (!expr) {
        continue;
      }
      try {
        katexRef.render(expr, block, {
          displayMode: true,
          throwOnError: false,
          strict: 'ignore',
        });
      } catch (_) {
        block.textContent = expr;
      }
    }
  }

  function waitForAssets(attempt) {
    var hasPendingImage = false;
    var images = document.images || [];
    for (var i = 0; i < images.length; i += 1) {
      var image = images[i];
      if (!image.complete) {
        hasPendingImage = true;
        break;
      }
    }

    var fontsReady = true;
    if (document.fonts && typeof document.fonts.status === 'string') {
      fontsReady = document.fonts.status === 'loaded';
    }

    if (hasPendingImage || !fontsReady) {
      if (attempt >= 240) {
        window.__SECONDLOOP_PDF_READY__ = true;
        return;
      }

      setTimeout(function () {
        waitForAssets(attempt + 1);
      }, 25);
      return;
    }

    window.__SECONDLOOP_PDF_READY__ = true;
  }

  function waitUntilReady(attempt) {
    if (window.katex && typeof window.katex.render === 'function') {
      renderLatexElements();
      waitForAssets(0);
      return;
    }

    if (attempt >= 240) {
      waitForAssets(0);
      return;
    }

    setTimeout(function () {
      waitUntilReady(attempt + 1);
    }, 25);
  }

  function bootstrap() {
    waitUntilReady(0);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootstrap, { once: true });
  } else {
    bootstrap();
  }
})();
</script>
</head>
<body>
$transformedHtml
</body>
</html>''';
}

String _transformRichTagHtml(String html) {
  final inlineTransformed =
      html.replaceAllMapped(_kHtmlLatexInlineTagPattern, (match) {
    final attributes = match.group(1) ?? '';
    final latex = _readHtmlAttribute(attributes, 'data-latex');
    if (latex == null || latex.trim().isEmpty) {
      return '';
    }
    return '<span class="sl-latex-inline" data-latex="$latex">$latex</span>';
  });

  final blockTransformed = inlineTransformed.replaceAllMapped(
    _kHtmlLatexBlockTagPattern,
    (match) {
      final attributes = match.group(1) ?? '';
      final latex = _readHtmlAttribute(attributes, 'data-latex');
      if (latex == null || latex.trim().isEmpty) {
        return '';
      }
      return '<div class="sl-latex-block" data-latex="$latex">$latex</div>';
    },
  );

  return blockTransformed.replaceAllMapped(_kHtmlMarkmapTagPattern, (match) {
    final attributes = match.group(1) ?? '';
    final source = _readHtmlAttribute(attributes, 'data-markmap');
    if (source == null || source.trim().isEmpty) {
      return '';
    }

    return '<pre class="sl-markmap-fallback"><code>$source</code></pre>';
  });
}

String? _readHtmlAttribute(String rawAttributes, String name) {
  final pattern = RegExp(
    '$name\\s*=\\s*("([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(rawAttributes);
  if (match == null) {
    return null;
  }

  return match.group(2) ?? match.group(3);
}

String _toCssColor(Color color) {
  if (color.alpha == 255) {
    final rgb = color.value & 0x00ffffff;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  final alpha = (color.alpha / 255).toStringAsFixed(3);
  return 'rgba(${color.red}, ${color.green}, ${color.blue}, $alpha)';
}
