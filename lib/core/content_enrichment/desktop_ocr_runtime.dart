import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/native_app_dir.dart';

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
    final appDir = await (appDirProvider ?? getNativeAppDir)();
    return _runtimeDirFromAppDir(appDir);
  } catch (_) {
    return null;
  }
}

Future<String?> resolveManagedDesktopOcrPythonExecutable({
  Future<String> Function()? appDirProvider,
}) async {
  final runtimeDir =
      await resolveDesktopOcrRuntimeDir(appDirProvider: appDirProvider);
  if (runtimeDir == null) return null;

  final candidates = <String>[
    '${runtimeDir.path}/python/bin/python3.11',
    '${runtimeDir.path}/python/bin/python3.10',
    '${runtimeDir.path}/python/bin/python3',
    '${runtimeDir.path}/python/bin/python',
    '${runtimeDir.path}/python/python.exe',
    '${runtimeDir.path}/python/python3.exe',
  ];

  for (final path in candidates) {
    try {
      if (await File(path).exists()) return path;
    } catch (_) {
      continue;
    }
  }
  return null;
}
