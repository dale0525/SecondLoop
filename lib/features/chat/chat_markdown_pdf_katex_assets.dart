import 'dart:convert';
import 'package:flutter/services.dart';

const String _kKatexCssAssetPath = 'assets/third_party/katex/katex.min.css';
const String _kKatexJsAssetPath = 'assets/third_party/katex/katex.min.js';
const String _kKatexFontsAssetDirectory = 'assets/third_party/katex/fonts';

final RegExp _kKatexCssFontUrlPattern = RegExp(
  r'''url\((["']?)fonts/([^"')]+)\1\)''',
  caseSensitive: false,
);
final RegExp _kInlineScriptClosePattern = RegExp(
  r'</script',
  caseSensitive: false,
);

Future<BundledKatexAssets>? _kBundledKatexAssetsFuture;

class BundledKatexAssets {
  const BundledKatexAssets({
    required this.css,
    required this.js,
  });

  final String css;
  final String js;
}

Future<BundledKatexAssets> loadBundledKatexAssets() {
  return _kBundledKatexAssetsFuture ??= _loadBundledKatexAssets();
}

Future<BundledKatexAssets> _loadBundledKatexAssets() async {
  final rawCss = await rootBundle.loadString(_kKatexCssAssetPath);
  final rawJs = await rootBundle.loadString(_kKatexJsAssetPath);
  final inlinedCss = await _inlineKatexFontDataUrls(rawCss);

  return BundledKatexAssets(
    css: inlinedCss,
    js: _escapeInlineScript(rawJs),
  );
}

Future<String> _inlineKatexFontDataUrls(String css) async {
  final fontFiles = _kKatexCssFontUrlPattern
      .allMatches(css)
      .map((match) => match.group(2))
      .whereType<String>()
      .toSet();
  if (fontFiles.isEmpty) {
    return css;
  }

  final replacementUrls = <String, String>{};
  for (final fileName in fontFiles) {
    if (!_shouldInlineFontAsset(fileName)) {
      continue;
    }

    final assetPath = '$_kKatexFontsAssetDirectory/$fileName';
    final bytes = await _loadAssetBytes(assetPath);
    final mimeType = _resolveFontMimeType(fileName);
    replacementUrls[fileName] =
        'url("data:$mimeType;base64,${base64Encode(bytes)}")';
  }

  return css.replaceAllMapped(_kKatexCssFontUrlPattern, (match) {
    final fileName = match.group(2);
    if (fileName == null) {
      return match.group(0) ?? '';
    }

    return replacementUrls[fileName] ?? (match.group(0) ?? '');
  });
}

bool _shouldInlineFontAsset(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.woff2') || lower.endsWith('.woff');
}

Future<Uint8List> _loadAssetBytes(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  return byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
}

String _resolveFontMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.woff2')) {
    return 'font/woff2';
  }
  if (lower.endsWith('.woff')) {
    return 'font/woff';
  }
  return 'application/octet-stream';
}

String _escapeInlineScript(String script) {
  return script.replaceAll(_kInlineScriptClosePattern, '<\\/script');
}
