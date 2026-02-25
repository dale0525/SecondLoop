import 'dart:io';

import 'package:flutter/foundation.dart';

Future<Uint8List?> loadMarkdownPdfImageBytes(
  String source, {
  HttpClient Function()? httpClientFactory,
}) async {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  UriData? uriData;
  try {
    uriData = UriData.parse(trimmed);
  } catch (_) {
    uriData = null;
  }
  if (uriData != null && uriData.mimeType.toLowerCase().startsWith('image/')) {
    try {
      final bytes = uriData.contentAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  if (_looksLikeWindowsAbsolutePath(trimmed)) {
    final file = File(trimmed);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (!await file.exists()) {
        return null;
      }
      return file.readAsBytes();
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _loadRemoteMarkdownPdfImageBytes(
        uri,
        httpClientFactory: httpClientFactory,
      );
    }

    return null;
  }

  final file = File(trimmed);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}

bool _looksLikeWindowsAbsolutePath(String value) {
  if (value.length >= 3) {
    final first = value.codeUnitAt(0);
    final isLetter =
        (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
    if (isLetter && value.codeUnitAt(1) == 58) {
      final separator = value.codeUnitAt(2);
      if (separator == 92 || separator == 47) {
        return true;
      }
    }
  }
  return value.startsWith(r'\\');
}

Future<Uint8List?> _loadRemoteMarkdownPdfImageBytes(
  Uri uri, {
  HttpClient Function()? httpClientFactory,
}) async {
  final client = (httpClientFactory ?? HttpClient.new)();
  client.connectionTimeout = const Duration(seconds: 15);

  try {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'SecondLoop-PdfExport/1.0',
    );

    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      return null;
    }

    return bytes;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
