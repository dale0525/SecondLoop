import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _kMarkdownPdfExportChannel =
    MethodChannel('secondloop/markdown_pdf_export');
const Duration _kWindowsPdfExportTimeout = Duration(seconds: 45);

bool isNativeMarkdownPdfExportSupported() {
  if (kIsWeb) {
    return false;
  }

  return Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
}

Future<Uint8List> exportMarkdownHtmlToPdfBytes({
  required String html,
  String? pageBackgroundColorHex,
}) async {
  if (kIsWeb) {
    throw UnsupportedError('Native markdown PDF export is unavailable on web');
  }

  if (Platform.isWindows) {
    return _exportMarkdownHtmlToPdfBytesOnWindows(html: html);
  }

  return _exportMarkdownHtmlToPdfBytesViaMethodChannel(
    html: html,
    pageBackgroundColorHex: pageBackgroundColorHex,
  );
}

Future<Uint8List> _exportMarkdownHtmlToPdfBytesViaMethodChannel({
  required String html,
  String? pageBackgroundColorHex,
}) async {
  final payload = _buildNativeMarkdownPdfPayload(
    html: html,
    pageBackgroundColorHex: pageBackgroundColorHex,
  );

  final bytes = await _kMarkdownPdfExportChannel.invokeMethod<Uint8List>(
    'exportMarkdownHtmlToPdf',
    payload,
  );

  if (bytes == null || bytes.isEmpty) {
    throw StateError('Native markdown PDF export returned empty content');
  }

  return bytes;
}

Map<String, Object> _buildNativeMarkdownPdfPayload({
  required String html,
  String? pageBackgroundColorHex,
}) {
  final payload = <String, Object>{
    'html': html,
  };

  final normalizedColorHex = _normalizePageBackgroundColorHex(
    pageBackgroundColorHex,
  );
  if (normalizedColorHex != null) {
    payload['pageBackgroundColorHex'] = normalizedColorHex;
  }

  return payload;
}

String? _normalizePageBackgroundColorHex(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final match = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(
    trimmed,
  );
  if (match == null) {
    return null;
  }

  return '#${match.group(1)!.toLowerCase()}';
}

@visibleForTesting
Map<String, Object> buildNativeMarkdownPdfPayloadForTest({
  required String html,
  String? pageBackgroundColorHex,
}) =>
    _buildNativeMarkdownPdfPayload(
      html: html,
      pageBackgroundColorHex: pageBackgroundColorHex,
    );

Future<Uint8List> _exportMarkdownHtmlToPdfBytesOnWindows({
  required String html,
}) async {
  final workingDirectory =
      await Directory.systemTemp.createTemp('secondloop_markdown_pdf_');

  try {
    final htmlFile = File('${workingDirectory.path}\\source.html');
    final outputFile = File('${workingDirectory.path}\\result.pdf');
    await htmlFile.writeAsString(html, flush: true);

    final executable = await _resolveWindowsHeadlessBrowserExecutable();
    if (executable == null) {
      throw StateError(
        'No supported Windows browser executable found for markdown PDF export',
      );
    }

    final errors = <String>[];
    final sourceUri = htmlFile.absolute.uri;
    for (final mode in <String>['new', 'legacy']) {
      final arguments = buildWindowsHeadlessPdfArguments(
        pdfOutputPath: outputFile.path,
        htmlSourceUri: sourceUri,
        headlessMode: mode,
      );

      ProcessResult processResult;
      try {
        processResult = await Process.run(
          executable,
          arguments,
        ).timeout(_kWindowsPdfExportTimeout);
      } on TimeoutException {
        errors.add('[$mode] timeout');
        continue;
      } catch (error) {
        errors.add('[$mode] process_error: $error');
        continue;
      }

      if (await outputFile.exists()) {
        final bytes = await outputFile.readAsBytes();
        if (bytes.isNotEmpty) {
          return bytes;
        }
      }

      final stderr = processResult.stderr?.toString() ?? '';
      final stdout = processResult.stdout?.toString() ?? '';
      errors.add(
        '[$mode] exit=${processResult.exitCode} stderr=${_truncateWindowsExportLog(stderr)} stdout=${_truncateWindowsExportLog(stdout)}',
      );
    }

    throw StateError(
      'Windows markdown PDF export failed: ${errors.join(' | ')}',
    );
  } finally {
    try {
      await workingDirectory.delete(recursive: true);
    } catch (_) {
      // Ignore cleanup failures.
    }
  }
}

Future<String?> _resolveWindowsHeadlessBrowserExecutable() async {
  final candidates = buildWindowsBrowserCandidatePaths(Platform.environment);
  for (final path in candidates) {
    if (path.trim().isEmpty) {
      continue;
    }

    final file = File(path);
    if (await file.exists()) {
      return file.path;
    }
  }

  for (final command in <String>['msedge', 'chrome', 'chromium']) {
    try {
      final result = await Process.run('where', <String>[command]);
      if (result.exitCode != 0) {
        continue;
      }

      final lines = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      for (final line in lines) {
        if (await File(line).exists()) {
          return line;
        }
      }
    } catch (_) {
      // Ignore and continue trying other commands.
    }
  }

  return null;
}

@visibleForTesting
List<String> buildWindowsBrowserCandidatePaths(
    Map<String, String> environment) {
  final roots = <String>[
    environment['PROGRAMFILES'] ?? '',
    environment['PROGRAMFILES(X86)'] ?? '',
    environment['LOCALAPPDATA'] ?? '',
    r'C:\Program Files',
    r'C:\Program Files (x86)',
  ];

  final suffixes = <String>[
    r'Microsoft\Edge\Application\msedge.exe',
    r'Google\Chrome\Application\chrome.exe',
    r'Chromium\Application\chrome.exe',
  ];

  final ordered = <String>[];
  final seen = <String>{};
  for (final root in roots) {
    final normalizedRoot = _normalizeWindowsPath(root);
    if (normalizedRoot.isEmpty) {
      continue;
    }

    for (final suffix in suffixes) {
      final candidate = '$normalizedRoot\\$suffix';
      final lower = candidate.toLowerCase();
      if (seen.add(lower)) {
        ordered.add(candidate);
      }
    }
  }

  return ordered;
}

@visibleForTesting
List<String> buildWindowsHeadlessPdfArguments({
  required String pdfOutputPath,
  required Uri htmlSourceUri,
  required String headlessMode,
}) {
  final headlessFlag = headlessMode == 'new' ? '--headless=new' : '--headless';

  return <String>[
    headlessFlag,
    '--disable-gpu',
    '--run-all-compositor-stages-before-draw',
    '--virtual-time-budget=20000',
    '--allow-file-access-from-files',
    '--print-to-pdf=$pdfOutputPath',
    htmlSourceUri.toString(),
  ];
}

String _normalizeWindowsPath(String value) {
  final normalized = value.replaceAll('/', '\\').trim();
  return normalized.replaceFirst(RegExp(r'[\\]+$'), '');
}

String _truncateWindowsExportLog(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '<empty>';
  }

  const limit = 280;
  if (normalized.length <= limit) {
    return normalized;
  }

  return '${normalized.substring(0, limit)}...';
}
