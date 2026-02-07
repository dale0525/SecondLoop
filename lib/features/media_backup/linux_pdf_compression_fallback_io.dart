import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/content_enrichment/linux_pdf_compress_resource_script.dart';
import '../../core/content_enrichment/linux_pdf_compress_resource_store.dart';

const Duration _kLinuxPdfCompressionTimeout = Duration(minutes: 5);
const Duration _kPythonProbeTimeout = Duration(seconds: 5);

Future<Uint8List?> tryCompressPdfViaLinuxFallback(
  Uint8List bytes, {
  required int scanDpi,
}) async {
  if (!Platform.isLinux || bytes.isEmpty) return null;

  final python = await _resolvePythonExecutable();
  if (python == null) return null;

  final dpi = scanDpi.clamp(150, 200);
  final tempDir = await Directory.systemTemp.createTemp(
    'secondloop_pdf_compress_',
  );
  final inputFile = File('${tempDir.path}/input.pdf');
  final outputFile = File('${tempDir.path}/output.pdf');

  try {
    await inputFile.writeAsBytes(bytes, flush: true);
    final bridgeScriptPath = await _resolveBridgeScriptPath(tempDir.path);
    if (bridgeScriptPath == null) return null;

    final bundledPythonPath = await _extractBundledPythonPath(tempDir.path);
    final installedResourceDir =
        await createLinuxPdfCompressResourceStore().readInstalledResourceDir();
    final installedPythonPath = installedResourceDir == null
        ? null
        : await _resolveInstalledPythonPath(installedResourceDir);

    final pythonPathEntries = <String>[
      if (installedPythonPath != null) installedPythonPath,
      if (bundledPythonPath != null) bundledPythonPath,
    ];
    final mergedPythonPath = _mergePythonPathEntries(pythonPathEntries);

    final result = await Process.run(
      python,
      <String>[
        bridgeScriptPath,
        '--input',
        inputFile.path,
        '--output',
        outputFile.path,
        '--dpi',
        '$dpi',
      ],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: <String, String>{
        'PYTHONUTF8': '1',
        if (mergedPythonPath != null) 'PYTHONPATH': mergedPythonPath,
      },
    ).timeout(
      _kLinuxPdfCompressionTimeout,
      onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
    );

    if (result.exitCode != 0) return null;
    if (!await outputFile.exists()) return null;

    final compressed = await outputFile.readAsBytes();
    if (compressed.isEmpty) return null;
    return compressed;
  } catch (_) {
    return null;
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<String?> _resolveBridgeScriptPath(String tempDirPath) async {
  try {
    final installedDir =
        await createLinuxPdfCompressResourceStore().readInstalledResourceDir();
    if (installedDir != null && installedDir.isNotEmpty) {
      final installedScript = File('$installedDir/pdf_scan_compress_bridge.py');
      if (await installedScript.exists()) {
        return installedScript.path;
      }
    }
  } catch (_) {}

  try {
    final file = File('$tempDirPath/pdf_scan_compress_bridge.py');
    await file.writeAsString(kLinuxPdfCompressBridgeScript, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<String?> _resolveInstalledPythonPath(String resourceDirPath) async {
  final pythonDir = Directory('$resourceDirPath/python');
  if (await pythonDir.exists()) {
    return pythonDir.path;
  }
  return null;
}

String? _mergePythonPathEntries(List<String> entries) {
  final normalized = <String>{};
  for (final entry in entries) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    normalized.add(trimmed);
  }
  final existing = (Platform.environment['PYTHONPATH'] ?? '').trim();
  if (existing.isNotEmpty) {
    for (final part in existing.split(':')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) normalized.add(trimmed);
    }
  }
  if (normalized.isEmpty) return null;
  return normalized.join(':');
}

Future<String?> _extractBundledPythonPath(String tempDirPath) async {
  try {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final decoded = jsonDecode(manifestRaw);
    if (decoded is! Map) return null;

    const prefix = 'assets/ocr/linux/python/';
    final assetKeys = decoded.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    if (assetKeys.isEmpty) return null;

    final outputRoot = Directory('$tempDirPath/bundled_linux_pdf_python');
    await outputRoot.create(recursive: true);

    for (final key in assetKeys) {
      final relative = key.substring(prefix.length);
      if (relative.isEmpty) continue;
      final outFile = File('${outputRoot.path}/$relative');
      await outFile.parent.create(recursive: true);
      final data = await rootBundle.load(key);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await outFile.writeAsBytes(bytes, flush: true);
    }

    return outputRoot.path;
  } catch (_) {
    return null;
  }
}

Future<String?> _resolvePythonExecutable() async {
  for (final candidate in const <String>['python3', 'python']) {
    try {
      final result = await Process.run(
        candidate,
        const <String>['--version'],
        runInShell: false,
      ).timeout(_kPythonProbeTimeout);
      if (result.exitCode == 0) return candidate;
    } catch (_) {
      continue;
    }
  }
  return null;
}
