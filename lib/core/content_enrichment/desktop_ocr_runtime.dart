import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../backend/native_app_dir.dart';

const String _kRuntimeAssetPrefix = 'assets/ocr/desktop_runtime/';
const String _kRuntimeManifestName =
    '_secondloop_desktop_runtime_manifest.json';
const Duration _kAppDirResolveTimeout = Duration(milliseconds: 800);

const List<String> _kDetModelAliases = <String>[
  'ch_PP-OCRv5_mobile_det.onnx',
  'ch_PP-OCRv4_det_infer.onnx',
  'ch_PP-OCRv3_det_infer.onnx',
];
const List<String> _kClsModelAliases = <String>[
  'ch_ppocr_mobile_v2.0_cls_infer.onnx',
];
const List<String> _kRecModelAliases = <String>[
  'ch_PP-OCRv5_rec_mobile_infer.onnx',
  'ch_PP-OCRv5_mobile_rec.onnx',
  'ch_PP-OCRv4_rec_infer.onnx',
  'ch_PP-OCRv3_rec_infer.onnx',
  'latin_PP-OCRv3_rec_infer.onnx',
  'arabic_PP-OCRv3_rec_infer.onnx',
  'cyrillic_PP-OCRv3_rec_infer.onnx',
  'devanagari_PP-OCRv3_rec_infer.onnx',
  'japan_PP-OCRv3_rec_infer.onnx',
  'korean_PP-OCRv3_rec_infer.onnx',
  'chinese_cht_PP-OCRv3_rec_infer.onnx',
];
const List<String> _kOnnxRuntimeLibAliases = <String>[
  'libonnxruntime.dylib',
  'libonnxruntime.so',
  'onnxruntime.dll',
];

Directory? _runtimeDirFromAppDir(String appDirPath) {
  if (!supportsDesktopManagedOcrRuntime()) return null;
  return Directory('$appDirPath/ocr/desktop/runtime');
}

bool supportsDesktopManagedOcrRuntime() {
  if (kIsWeb) return false;
  if (Platform.isLinux) return true;
  if (Platform.isMacOS) return true;
  if (Platform.isWindows) return true;
  return false;
}

Future<Directory?> resolveDesktopOcrRuntimeDir({
  Future<String> Function()? appDirProvider,
}) async {
  if (!supportsDesktopManagedOcrRuntime()) return null;
  try {
    final appDir = await (appDirProvider ?? getNativeAppDir)()
        .timeout(_kAppDirResolveTimeout);
    return _runtimeDirFromAppDir(appDir);
  } catch (_) {
    return null;
  }
}

final class DesktopRuntimeHealth {
  const DesktopRuntimeHealth({
    required this.supported,
    required this.installed,
    required this.runtimeDirPath,
    required this.fileCount,
    required this.totalBytes,
    this.message,
  });

  final bool supported;
  final bool installed;
  final String? runtimeDirPath;
  final int fileCount;
  final int totalBytes;
  final String? message;
}

Future<DesktopRuntimeHealth> readDesktopRuntimeHealth({
  Future<String> Function()? appDirProvider,
}) async {
  if (!supportsDesktopManagedOcrRuntime()) {
    return const DesktopRuntimeHealth(
      supported: false,
      installed: false,
      runtimeDirPath: null,
      fileCount: 0,
      totalBytes: 0,
    );
  }

  final runtimeDir =
      await resolveDesktopOcrRuntimeDir(appDirProvider: appDirProvider);
  if (runtimeDir == null || !await runtimeDir.exists()) {
    return const DesktopRuntimeHealth(
      supported: true,
      installed: false,
      runtimeDirPath: null,
      fileCount: 0,
      totalBytes: 0,
      message: 'runtime_missing',
    );
  }

  var fileCount = 0;
  var totalBytes = 0;
  final runtimeBasenames = <String>{};
  await for (final entity in runtimeDir.list(recursive: true)) {
    if (entity is! File) continue;
    final stat = await entity.stat();
    fileCount += 1;
    totalBytes += stat.size;
    final basename = _basenameFromAnyPath(entity.path);
    if (basename.isNotEmpty) {
      runtimeBasenames.add(basename);
    }
  }

  final manifestFile = File('${runtimeDir.path}/$_kRuntimeManifestName');
  final hasManifest = await manifestFile.exists();
  final hasPayload = _hasRequiredRuntimePayload(runtimeBasenames);
  final installed = hasManifest && hasPayload;

  String? message;
  if (!installed) {
    if (!hasManifest) {
      message = 'runtime_not_initialized';
    } else if (!hasPayload) {
      message = 'runtime_payload_incomplete';
    } else {
      message = 'runtime_not_initialized';
    }
  }

  return DesktopRuntimeHealth(
    supported: true,
    installed: installed,
    runtimeDirPath: installed ? runtimeDir.path : null,
    fileCount: fileCount,
    totalBytes: totalBytes,
    message: message,
  );
}

Future<DesktopRuntimeHealth> repairDesktopRuntimeInstall({
  Future<String> Function()? appDirProvider,
}) async {
  if (!supportsDesktopManagedOcrRuntime()) {
    throw StateError('desktop_runtime_not_supported');
  }

  final runtimeDir =
      await resolveDesktopOcrRuntimeDir(appDirProvider: appDirProvider);
  if (runtimeDir == null) {
    throw StateError('desktop_runtime_dir_unavailable');
  }

  if (await runtimeDir.exists()) {
    await runtimeDir.delete(recursive: true);
  }
  await runtimeDir.create(recursive: true);

  var copiedAssets = 0;
  final assetKeys = await _runtimeAssetKeysFromBundle();
  for (final key in assetKeys) {
    final relative = key.substring(_kRuntimeAssetPrefix.length);
    if (relative.trim().isEmpty) continue;

    ByteData data;
    try {
      data = await rootBundle.load(key);
    } catch (_) {
      continue;
    }

    final outFile = File('${runtimeDir.path}/$relative');
    await outFile.parent.create(recursive: true);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await outFile.writeAsBytes(bytes, flush: true);
    copiedAssets += 1;
  }

  final manifestFile = File('${runtimeDir.path}/$_kRuntimeManifestName');
  final payload = <String, Object?>{
    'runtime': 'desktop_media',
    'version': 'v1',
    'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
    'copied_asset_count': copiedAssets,
  };
  await manifestFile.writeAsString(jsonEncode(payload), flush: true);

  return readDesktopRuntimeHealth(appDirProvider: appDirProvider);
}

Future<void> clearDesktopRuntimeInstall({
  Future<String> Function()? appDirProvider,
}) async {
  final runtimeDir =
      await resolveDesktopOcrRuntimeDir(appDirProvider: appDirProvider);
  if (runtimeDir == null) return;
  if (await runtimeDir.exists()) {
    await runtimeDir.delete(recursive: true);
  }
}

Future<List<String>> _runtimeAssetKeysFromBundle() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((key) => key.startsWith(_kRuntimeAssetPrefix))
        .toList(growable: false);
  } catch (_) {
    // Keep compatibility with toolchains that still expose JSON only.
  }

  try {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final decoded = jsonDecode(manifestRaw);
    if (decoded is Map) {
      return decoded.keys
          .whereType<String>()
          .where((key) => key.startsWith(_kRuntimeAssetPrefix))
          .toList(growable: false);
    }
  } catch (_) {
    // Runtime copy falls back to writing only install marker.
  }

  return const <String>[];
}

String _basenameFromAnyPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex < 0 || slashIndex + 1 >= normalized.length) {
    return normalized;
  }
  return normalized.substring(slashIndex + 1);
}

bool _containsAnyAlias(Set<String> basenames, List<String> aliases) {
  for (final alias in aliases) {
    if (basenames.contains(alias)) {
      return true;
    }
  }
  return false;
}

bool _hasRequiredRuntimePayload(Set<String> basenames) {
  return _containsAnyAlias(basenames, _kDetModelAliases) &&
      _containsAnyAlias(basenames, _kClsModelAliases) &&
      _containsAnyAlias(basenames, _kRecModelAliases) &&
      _containsAnyAlias(basenames, _kOnnxRuntimeLibAliases);
}
