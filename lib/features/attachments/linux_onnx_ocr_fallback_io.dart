import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/content_enrichment/desktop_ocr_runtime.dart';
import '../../core/content_enrichment/linux_ocr_model_store.dart';
import 'linux_onnx_ocr_script.dart';

const Duration _kLinuxOnnxOcrTimeout = Duration(minutes: 5);
const Duration _kPythonProbeTimeout = Duration(seconds: 5);
const String _kRuntimeManifestFileName = '_secondloop_runtime_manifest.json';

bool _supportsDesktopOnnxOcr() {
  if (Platform.isLinux) return true;
  if (Platform.isMacOS) return true;
  if (Platform.isWindows) return true;
  return false;
}

Future<Object?> tryOcrPdfViaLinuxOnnx(
  Uint8List bytes, {
  required int maxPages,
  required int dpi,
  required String languageHints,
}) async {
  if (!_supportsDesktopOnnxOcr() || bytes.isEmpty) return null;

  final safeMaxPages = maxPages.clamp(1, 10000);
  final safeDpi = dpi.clamp(72, 600);
  final hints =
      languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

  return _runLinuxOnnxBridge(
    mode: 'pdf',
    bytes: bytes,
    inputSuffix: '.pdf',
    modeArgs: <String>[
      '--max-pages',
      '$safeMaxPages',
      '--dpi',
      '$safeDpi',
      '--language-hints',
      hints,
    ],
  );
}

Future<Object?> tryOcrImageViaLinuxOnnx(
  Uint8List bytes, {
  required String languageHints,
}) async {
  if (!_supportsDesktopOnnxOcr() || bytes.isEmpty) return null;

  final hints =
      languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

  return _runLinuxOnnxBridge(
    mode: 'image',
    bytes: bytes,
    inputSuffix: '.img',
    modeArgs: <String>[
      '--language-hints',
      hints,
    ],
  );
}

Future<Object?> _runLinuxOnnxBridge({
  required String mode,
  required Uint8List bytes,
  required String inputSuffix,
  required List<String> modeArgs,
}) async {
  final python = await _resolvePythonExecutable();
  if (python == null) return null;

  final tempDir = await Directory.systemTemp.createTemp('secondloop_ocr_');
  final scriptFile = File('${tempDir.path}/linux_onnx_ocr_bridge.py');
  final inputFile = File('${tempDir.path}/input$inputSuffix');

  try {
    await scriptFile.writeAsString(kLinuxOnnxOcrBridgeScript, flush: true);
    await inputFile.writeAsBytes(bytes, flush: true);
    final bundledRuntime = await _extractBundledLinuxOnnxRuntime(tempDir);
    final runtimeSitePackages = await _resolveManagedRuntimeSitePackagesPath();
    final installedModelDir = await _readInstalledLinuxOcrModelDir();
    final pythonPath = _combinePythonPaths(
      bundledRuntime.pythonPath,
      runtimeSitePackages,
    );

    final args = <String>[
      scriptFile.path,
      '--mode',
      mode,
      '--input',
      inputFile.path,
      ...modeArgs,
    ];

    final result = await Process.run(
      python,
      args,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: <String, String>{
        'PYTHONUTF8': '1',
        if (pythonPath != null) 'PYTHONPATH': pythonPath,
        if (installedModelDir != null)
          'SECONDLOOP_OCR_MODEL_DIR': installedModelDir
        else if (bundledRuntime.modelDir != null)
          'SECONDLOOP_OCR_MODEL_DIR': bundledRuntime.modelDir!,
      },
    ).timeout(
      _kLinuxOnnxOcrTimeout,
      onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
    );

    if (result.exitCode != 0) return null;
    final output = (result.stdout as String?)?.trim() ?? '';
    if (output.isEmpty) return null;

    final decoded = jsonDecode(output);
    if (decoded is Map) {
      return decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return output;
  } catch (_) {
    return null;
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<String?> _readInstalledLinuxOcrModelDir() async {
  try {
    return createLinuxOcrModelStore().readInstalledModelDir();
  } catch (_) {
    return null;
  }
}

Future<String?> _resolvePythonExecutable() async {
  try {
    final managed = await resolveManagedDesktopOcrPythonExecutable();
    if (managed != null) {
      final ready = await _probePython(managed);
      if (ready) return managed;
    }
  } catch (_) {}

  try {
    final runtimePreferred = await _resolveRuntimeManifestPythonExecutable();
    if (runtimePreferred != null) {
      final ready = await _probePython(runtimePreferred);
      if (ready) return runtimePreferred;
    }
  } catch (_) {}

  final candidates = <String>[
    'python3',
    'python',
    if (!Platform.isWindows) ...<String>[
      '/usr/bin/python3',
      '/usr/local/bin/python3',
    ],
    if (Platform.isMacOS) ...<String>[
      '/opt/homebrew/bin/python3',
      '/opt/local/bin/python3',
    ],
  ];
  for (final candidate in candidates) {
    try {
      final ready = await _probePython(candidate);
      if (ready) return candidate;
    } catch (_) {
      continue;
    }
  }
  return null;
}

Future<bool> _probePython(String executable) async {
  final result = await Process.run(
    executable,
    const <String>['--version'],
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  ).timeout(_kPythonProbeTimeout);
  if (result.exitCode != 0) return false;
  final out = ((result.stdout as String?) ?? '').trim();
  final err = ((result.stderr as String?) ?? '').trim();
  return '$out $err'.contains('Python ');
}

Future<String?> _resolveManagedRuntimeSitePackagesPath() async {
  final runtimeDir = await resolveDesktopOcrRuntimeDir();
  if (runtimeDir == null) return null;
  final candidates = <String>[
    '${runtimeDir.path}/site-packages',
    '${runtimeDir.path}/python/Lib/site-packages',
  ];
  final pythonLibRoot = Directory('${runtimeDir.path}/python/lib');
  if (await pythonLibRoot.exists()) {
    await for (final child in pythonLibRoot.list(followLinks: false)) {
      if (child is! Directory) continue;
      final name = child.path.split('/').last;
      if (!name.startsWith('python')) continue;
      candidates.add('${child.path}/site-packages');
    }
  }

  for (final path in candidates) {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      final moduleDir = Directory('$path/rapidocr_onnxruntime');
      final moduleFile = File('$path/rapidocr_onnxruntime.py');
      if (await moduleDir.exists() || await moduleFile.exists()) {
        return path;
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

Future<String?> _resolveRuntimeManifestPythonExecutable() async {
  final runtimeDir = await resolveDesktopOcrRuntimeDir();
  if (runtimeDir == null) return null;
  final manifestFile = File('${runtimeDir.path}/$_kRuntimeManifestFileName');
  if (!await manifestFile.exists()) return null;
  try {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map) return null;
    final path = decoded['python_executable']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return path;
  } catch (_) {
    return null;
  }
}

String? _combinePythonPaths(String? first, String? second) {
  final values = <String>[
    if (first != null && first.trim().isNotEmpty) first.trim(),
    if (second != null && second.trim().isNotEmpty) second.trim(),
  ];
  if (values.isEmpty) return null;
  return values.join(Platform.pathSeparator);
}

final class _BundledLinuxOnnxRuntime {
  const _BundledLinuxOnnxRuntime({
    this.pythonPath,
    this.modelDir,
  });

  final String? pythonPath;
  final String? modelDir;
}

Future<_BundledLinuxOnnxRuntime> _extractBundledLinuxOnnxRuntime(
  Directory tempDir,
) async {
  try {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final decoded = jsonDecode(manifestRaw);
    if (decoded is! Map) return const _BundledLinuxOnnxRuntime();

    const prefix = 'assets/ocr/linux/';
    final assetKeys = decoded.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    if (assetKeys.isEmpty) return const _BundledLinuxOnnxRuntime();

    final bundleRoot = Directory('${tempDir.path}/bundled_linux_ocr');
    await bundleRoot.create(recursive: true);
    for (final key in assetKeys) {
      final relative = key.substring(prefix.length);
      if (relative.isEmpty) continue;
      final outFile = File('${bundleRoot.path}/$relative');
      await outFile.parent.create(recursive: true);
      final data = await rootBundle.load(key);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await outFile.writeAsBytes(bytes, flush: true);
    }

    final pythonDir = Directory('${bundleRoot.path}/python');
    final modelDir = Directory('${bundleRoot.path}/models');
    final pythonPath = await pythonDir.exists() ? pythonDir.path : null;
    final modelPath = await modelDir.exists() ? modelDir.path : null;

    return _BundledLinuxOnnxRuntime(
      pythonPath: pythonPath,
      modelDir: modelPath,
    );
  } catch (_) {
    return const _BundledLinuxOnnxRuntime();
  }
}
