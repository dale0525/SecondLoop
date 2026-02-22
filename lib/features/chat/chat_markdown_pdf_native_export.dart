import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _kMarkdownPdfExportChannel =
    MethodChannel('secondloop/markdown_pdf_export');

bool isNativeMarkdownPdfExportSupported() {
  if (kIsWeb) {
    return false;
  }

  return Platform.isAndroid || Platform.isMacOS;
}

Future<Uint8List> exportMarkdownHtmlToPdfBytes({
  required String html,
}) async {
  final payload = <String, Object>{
    'html': html,
  };

  final bytes = await _kMarkdownPdfExportChannel.invokeMethod<Uint8List>(
    'exportMarkdownHtmlToPdf',
    payload,
  );

  if (bytes == null || bytes.isEmpty) {
    throw StateError('Native markdown PDF export returned empty content');
  }

  return bytes;
}
