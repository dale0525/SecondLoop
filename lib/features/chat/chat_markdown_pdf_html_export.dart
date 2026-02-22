import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'chat_markdown_rich_rendering.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

final RegExp _kMarkdownImagePattern = RegExp(
  r'!\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)',
);
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

const int _kMaxInlinedImageBytes = 8 * 1024 * 1024;
const Duration _kRemoteImageTimeout = Duration(seconds: 8);

Future<String> buildChatMarkdownPdfHtmlDocument({
  required String markdown,
  required ChatMarkdownPreviewTheme theme,
  required String emptyFallback,
}) async {
  final normalized = sanitizeChatMarkdown(markdown).trim();
  final hydratedMarkdown = await _inlineMarkdownImageSources(
      normalized.isEmpty ? markdown : normalized);
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

  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
<style>
@page {
  size: A4;
  margin: 48px 54px 64px 54px;
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
}
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Helvetica Neue", Arial, "Noto Sans", sans-serif;
  font-size: 13px;
  line-height: 1.45;
  color: ${_toCssColor(theme.textColor)};
  background: ${_toCssColor(theme.panelColor)};
  word-break: break-word;
  overflow-wrap: anywhere;
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
.katex-display,
.sl-markmap-fallback {
  break-inside: avoid-page;
  page-break-inside: avoid;
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
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
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

  function waitUntilReady(attempt) {
    if (window.katex && typeof window.katex.render === 'function') {
      renderLatexElements();
      window.__SECONDLOOP_PDF_READY__ = true;
      return;
    }

    if (attempt >= 240) {
      window.__SECONDLOOP_PDF_READY__ = true;
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

Future<String> _inlineMarkdownImageSources(String markdown) async {
  if (markdown.isEmpty) {
    return markdown;
  }

  final matches =
      _kMarkdownImagePattern.allMatches(markdown).toList(growable: false);
  if (matches.isEmpty) {
    return markdown;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    buffer.write(markdown.substring(cursor, match.start));
    final imageSegment = match.group(0);
    final sourceToken = match.group(1);

    if (imageSegment == null || sourceToken == null) {
      buffer.write(markdown.substring(match.start, match.end));
      cursor = match.end;
      continue;
    }

    final source = _unwrapMarkdownImageSource(sourceToken);
    final dataUrl = await _resolveImageSourceAsDataUrl(source);
    if (dataUrl == null) {
      buffer.write(imageSegment);
      cursor = match.end;
      continue;
    }

    final replacementSource =
        sourceToken.startsWith('<') ? '<$dataUrl>' : dataUrl;
    buffer.write(imageSegment.replaceFirst(sourceToken, replacementSource));
    cursor = match.end;
  }

  buffer.write(markdown.substring(cursor));
  return buffer.toString();
}

String _unwrapMarkdownImageSource(String token) {
  if (token.startsWith('<') && token.endsWith('>') && token.length > 2) {
    return token.substring(1, token.length - 1);
  }
  return token;
}

Future<String?> _resolveImageSourceAsDataUrl(String source) async {
  final trimmed = source.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) {
    return trimmed.isEmpty ? null : trimmed;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return _readLocalImageAsDataUrl(trimmed);
  }

  if (uri.hasScheme) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _downloadImageAsDataUrl(uri);
    }
    if (uri.scheme == 'file') {
      return _readLocalImageAsDataUrl(uri.toFilePath());
    }
    return null;
  }

  return _readLocalImageAsDataUrl(trimmed);
}

Future<String?> _downloadImageAsDataUrl(Uri uri) async {
  HttpClient? client;

  try {
    client = HttpClient()..connectionTimeout = _kRemoteImageTimeout;
    final request = await client.getUrl(uri).timeout(_kRemoteImageTimeout);
    request.followRedirects = true;
    request.maxRedirects = 4;
    request.headers
        .set(HttpHeaders.userAgentHeader, 'SecondLoopMarkdownPdfExporter/1.0');

    final response = await request.close().timeout(_kRemoteImageTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final bytes = await _readHttpResponseBytes(response);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final mimeType = _resolveMimeType(
      headerMimeType: response.headers.contentType?.mimeType,
      sourcePath: uri.path,
      bytes: bytes,
    );
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}

Future<List<int>?> _readHttpResponseBytes(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);
  var totalBytes = 0;

  await for (final chunk in response) {
    totalBytes += chunk.length;
    if (totalBytes > _kMaxInlinedImageBytes) {
      return null;
    }
    builder.add(chunk);
  }

  return builder.takeBytes();
}

Future<String?> _readLocalImageAsDataUrl(String path) async {
  if (path.trim().isEmpty) {
    return null;
  }

  try {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final length = await file.length();
    if (length <= 0 || length > _kMaxInlinedImageBytes) {
      return null;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }

    final mimeType = _resolveMimeType(
      headerMimeType: null,
      sourcePath: file.path,
      bytes: bytes,
    );
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

String _resolveMimeType({
  required String? headerMimeType,
  required String sourcePath,
  required List<int> bytes,
}) {
  if (headerMimeType != null && headerMimeType.startsWith('image/')) {
    return headerMimeType;
  }

  final lowerPath = sourcePath.toLowerCase();
  if (lowerPath.endsWith('.png')) return 'image/png';
  if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lowerPath.endsWith('.gif')) return 'image/gif';
  if (lowerPath.endsWith('.webp')) return 'image/webp';
  if (lowerPath.endsWith('.bmp')) return 'image/bmp';
  if (lowerPath.endsWith('.svg')) return 'image/svg+xml';

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6) {
    final header = ascii.decode(bytes.take(6).toList(), allowInvalid: true);
    if (header == 'GIF87a' || header == 'GIF89a') {
      return 'image/gif';
    }
  }

  final probeLength = math.min(400, bytes.length);
  final probeText = utf8
      .decode(bytes.sublist(0, probeLength), allowMalformed: true)
      .toLowerCase();
  if (probeText.contains('<svg')) {
    return 'image/svg+xml';
  }

  return 'application/octet-stream';
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
