import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../backend/native_app_dir.dart';

const String _kWindowsFfmpegAssetPath = 'assets/bin/ffmpeg/windows/ffmpeg.zip';
const String _kMacosFfmpegAssetPath = 'assets/bin/ffmpeg/macos/ffmpeg';
const String _kLinuxFfmpegAssetPath = 'assets/bin/ffmpeg/linux/ffmpeg';
const String _kWindowsFfmpegExecutableName = 'ffmpeg.exe';
const String _kUnixFfmpegExecutableName = 'ffmpeg';

String? _cachedResolvedFfmpegExecutablePath;
Future<String?>? _ffmpegResolutionFuture;

Future<String?> resolveBundledFfmpegExecutablePath() async {
  final cachedPath = _cachedResolvedFfmpegExecutablePath;
  if (cachedPath != null) {
    try {
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
    } catch (_) {}
    _cachedResolvedFfmpegExecutablePath = null;
  }

  final inFlight = _ffmpegResolutionFuture;
  if (inFlight != null) {
    return inFlight;
  }

  final future = resolveBundledFfmpegExecutablePathForTest(
    isWeb: kIsWeb,
    isWindows: !kIsWeb && Platform.isWindows,
    isMacOS: !kIsWeb && Platform.isMacOS,
    isLinux: !kIsWeb && Platform.isLinux,
    loadAssetBytes: _loadAssetBytes,
    appDirProvider: getNativeAppDir,
    systemPathResolver: _resolveSystemFfmpegExecutablePath,
  );
  _ffmpegResolutionFuture = future;

  try {
    final resolved = await future;
    if (resolved != null) {
      try {
        if (await File(resolved).exists()) {
          _cachedResolvedFfmpegExecutablePath = resolved;
        } else {
          _cachedResolvedFfmpegExecutablePath = null;
        }
      } catch (_) {
        _cachedResolvedFfmpegExecutablePath = null;
      }
    } else {
      _cachedResolvedFfmpegExecutablePath = null;
    }
    return resolved;
  } finally {
    if (identical(_ffmpegResolutionFuture, future)) {
      _ffmpegResolutionFuture = null;
    }
  }
}

Future<String?> resolveBundledFfmpegExecutablePathForTest({
  required bool isWeb,
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required Future<Uint8List?> Function(String assetPath) loadAssetBytes,
  required Future<String> Function() appDirProvider,
  required Future<String?> Function() systemPathResolver,
}) async {
  if (isWeb) {
    return null;
  }

  final assetPath = _bundledFfmpegAssetPath(
    isWindows: isWindows,
    isMacOS: isMacOS,
    isLinux: isLinux,
  );

  if (assetPath != null) {
    try {
      final bundledBytes = await loadAssetBytes(assetPath);
      if (bundledBytes != null && bundledBytes.isNotEmpty) {
        final appDir = (await appDirProvider()).trim();
        if (appDir.isNotEmpty) {
          final resolved = await _materializeBundledFfmpegExecutable(
            appDir: appDir,
            bundledBytes: bundledBytes,
            isWindows: isWindows,
            isMacOS: isMacOS,
            isLinux: isLinux,
          );
          if (resolved != null) {
            return resolved;
          }
        }
      }
    } catch (_) {}
  }

  try {
    return await systemPathResolver();
  } catch (_) {
    return null;
  }
}

String bundledFfmpegPayloadIdForTest(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return 'fnv1a64_${hash.toRadixString(16).padLeft(16, '0')}';
}

Future<Uint8List?> _loadAssetBytes(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

String? _bundledFfmpegAssetPath({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
}) {
  if (isWindows) return _kWindowsFfmpegAssetPath;
  if (isMacOS) return _kMacosFfmpegAssetPath;
  if (isLinux) return _kLinuxFfmpegAssetPath;
  return null;
}

String _bundledFfmpegExecutableName({
  required bool isWindows,
}) {
  if (isWindows) {
    return _kWindowsFfmpegExecutableName;
  }
  return _kUnixFfmpegExecutableName;
}

Future<String?> _materializeBundledFfmpegExecutable({
  required String appDir,
  required Uint8List bundledBytes,
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
}) async {
  if (!(isWindows || isMacOS || isLinux)) {
    return null;
  }

  final executableName = _bundledFfmpegExecutableName(isWindows: isWindows);
  final payloadId = bundledFfmpegPayloadIdForTest(bundledBytes);
  final executablePath = _joinPath(
    appDir,
    <String>['bin', 'ffmpeg', payloadId, executableName],
  );
  final executableFile = File(executablePath);

  try {
    if (await executableFile.exists()) {
      final existingLength = await executableFile.length();
      if (existingLength > 0) {
        return executableFile.path;
      }
      await executableFile.delete();
    }
  } catch (_) {}

  final tempFile = File('${executableFile.path}.tmp');
  try {
    await executableFile.parent.create(recursive: true);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final outputBytes = isWindows
        ? _extractBundledExecutableFromZip(
            zipBytes: bundledBytes,
            executableName: executableName,
          )
        : bundledBytes;
    if (outputBytes == null || outputBytes.isEmpty) {
      return null;
    }

    await tempFile.writeAsBytes(outputBytes, flush: true);

    if (!isWindows) {
      final chmodResult =
          await Process.run('chmod', <String>['755', tempFile.path]);
      if (chmodResult.exitCode != 0) {
        try {
          await tempFile.delete();
        } catch (_) {}
        return null;
      }
    }

    try {
      await tempFile.rename(executableFile.path);
    } catch (_) {
      if (await executableFile.exists()) {
        final existingLength = await executableFile.length();
        try {
          await tempFile.delete();
        } catch (_) {}
        if (existingLength > 0) {
          return executableFile.path;
        }
      }
      rethrow;
    }

    final length = await executableFile.length();
    if (length <= 0) {
      try {
        await executableFile.delete();
      } catch (_) {}
      return null;
    }
    return executableFile.path;
  } catch (_) {
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}
    return null;
  }
}

Uint8List? _extractBundledExecutableFromZip({
  required Uint8List zipBytes,
  required String executableName,
}) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
  } catch (_) {
    return null;
  }

  final normalizedName = executableName.trim().toLowerCase();
  for (final file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final archiveName = file.name.replaceAll('\\', '/');
    final separatorIndex = archiveName.lastIndexOf('/');
    final basename = separatorIndex >= 0
        ? archiveName.substring(separatorIndex + 1)
        : archiveName;
    if (basename.trim().toLowerCase() != normalizedName) {
      continue;
    }

    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return bytes;
  }

  return null;
}

Future<String?> _resolveSystemFfmpegExecutablePath() async {
  final pathEnv = Platform.environment['PATH'] ?? '';
  if (pathEnv.trim().isEmpty) {
    return null;
  }

  final pathSeparator = Platform.isWindows ? ';' : ':';
  final executableNames = Platform.isWindows
      ? const <String>['ffmpeg.exe', 'ffmpeg']
      : const <String>['ffmpeg'];

  for (final rawEntry in pathEnv.split(pathSeparator)) {
    final entry = _trimOuterQuotes(rawEntry.trim());
    if (entry.isEmpty) {
      continue;
    }
    for (final executableName in executableNames) {
      final candidatePath = _joinPath(entry, <String>[executableName]);
      try {
        final candidateFile = File(candidatePath);
        if (await candidateFile.exists()) {
          return candidateFile.path;
        }
      } catch (_) {}
    }
  }

  return null;
}

String _trimOuterQuotes(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _joinPath(String root, List<String> segments) {
  final separator = Platform.pathSeparator;
  var result = root;
  for (final rawSegment in segments) {
    final segment = rawSegment.trim();
    if (segment.isEmpty) {
      continue;
    }
    if (result.endsWith(separator) ||
        result.endsWith('/') ||
        result.endsWith('\\')) {
      result = '$result$segment';
    } else {
      result = '$result$separator$segment';
    }
  }
  return result;
}
