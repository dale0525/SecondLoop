import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../backend/native_app_dir.dart';

const String _kRuntimeAssetPrefix = 'assets/ocr/desktop_runtime/';
const String _kRuntimeManifestName =
    '_secondloop_desktop_runtime_manifest.json';
const Duration _kAppDirResolveTimeout = Duration(milliseconds: 800);

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
  await for (final entity in runtimeDir.list(recursive: true)) {
    if (entity is! File) continue;
    final stat = await entity.stat();
    fileCount += 1;
    totalBytes += stat.size;
  }

  final manifestFile = File('${runtimeDir.path}/$_kRuntimeManifestName');
  final installed = await manifestFile.exists() && fileCount > 0;
  return DesktopRuntimeHealth(
    supported: true,
    installed: installed,
    runtimeDirPath: installed ? runtimeDir.path : null,
    fileCount: fileCount,
    totalBytes: totalBytes,
    message: installed ? null : 'runtime_not_initialized',
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
  try {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final decoded = jsonDecode(manifestRaw);
    if (decoded is Map) {
      final assetKeys = decoded.keys
          .whereType<String>()
          .where((key) => key.startsWith(_kRuntimeAssetPrefix));
      for (final key in assetKeys) {
        final relative = key.substring(_kRuntimeAssetPrefix.length);
        if (relative.trim().isEmpty) continue;
        final outFile = File('${runtimeDir.path}/$relative');
        await outFile.parent.create(recursive: true);
        final data = await rootBundle.load(key);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await outFile.writeAsBytes(bytes, flush: true);
        copiedAssets += 1;
      }
    }
  } catch (_) {
    // Best-effort: runtime can still be marked installed for pure Rust path.
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
