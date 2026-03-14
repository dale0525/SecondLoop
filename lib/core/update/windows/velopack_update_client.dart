import 'dart:io';

import 'velopack_paths.dart';

typedef VelopackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef VelopackProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

abstract class WindowsStagedUpdateClient {
  bool isAvailable();

  Future<void> stageAsset(Uri assetDownloadUri);

  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  });

  Future<void> applyPendingOnStartup();

  Future<void> applyPendingAndRestart({
    required int waitPid,
  });
}

class VelopackUpdateClient implements WindowsStagedUpdateClient {
  VelopackUpdateClient({
    String? updateExecutablePath,
    VelopackProcessRunner? processRunner,
    VelopackProcessStarter? processStarter,
  })  : _updateExecutablePath = updateExecutablePath,
        _processRunner = processRunner ?? _defaultProcessRunner,
        _processStarter = processStarter ?? _defaultProcessStarter;

  final String? _updateExecutablePath;
  final VelopackProcessRunner _processRunner;
  final VelopackProcessStarter _processStarter;

  String get _updateExePath =>
      _updateExecutablePath ?? resolveVelopackUpdateExePath();

  @override
  bool isAvailable() {
    final updateExe = File(_updateExePath);
    if (!updateExe.existsSync()) {
      return false;
    }

    final appRoot = updateExe.absolute.parent.path;
    final sqVersionPath = File(
      '$appRoot${Platform.pathSeparator}current${Platform.pathSeparator}sq.version',
    );
    return sqVersionPath.existsSync();
  }

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {
    if (!isAvailable()) {
      throw StateError('windows_velopack_unavailable');
    }

    await _stageAssetFile(assetDownloadUri);
  }

  @override
  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  }) async {
    if (!isAvailable()) {
      throw StateError('windows_velopack_unavailable');
    }

    final packageFile = await _stageAssetFile(assetDownloadUri);
    await _processStarter(
      _updateExePath,
      [
        'apply',
        '--silent',
        '--waitPid',
        waitPid.toString(),
        '--package',
        packageFile.path,
      ],
      mode: ProcessStartMode.detached,
    );
  }

  @override
  Future<void> applyPendingOnStartup() async {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      throw StateError('windows_velopack_unavailable');
    }

    if (!_hasPendingPackageUpdate(updateExePath)) {
      return;
    }

    final result = await _processRunner(updateExePath, [
      'apply',
      '--silent',
    ]);

    if (result.exitCode != 0) {
      _deletePendingPackageUpdates(updateExePath);
      throw StateError('windows_velopack_apply_failed_${result.stderr}');
    }
  }

  @override
  Future<void> applyPendingAndRestart({
    required int waitPid,
  }) async {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      throw StateError('windows_velopack_unavailable');
    }

    if (!_hasPendingPackageUpdate(updateExePath)) {
      throw StateError('windows_velopack_no_pending_update');
    }

    await _processStarter(
      updateExePath,
      [
        'apply',
        '--silent',
        '--waitPid',
        waitPid.toString(),
      ],
      mode: ProcessStartMode.detached,
    );
  }

  Future<File> _stageAssetFile(Uri assetDownloadUri) async {
    final updateExePath = _updateExePath;
    final packagesDir = _resolvePackagesDirectory(updateExePath);
    await packagesDir.create(recursive: true);

    final packageFile = File(
      '${packagesDir.path}${Platform.pathSeparator}${_resolveLocalPackageFileName(assetDownloadUri)}',
    );
    await _downloadAssetToFile(assetDownloadUri, packageFile);
    return packageFile;
  }

  static Directory _resolvePackagesDirectory(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    return Directory('$appRoot${Platform.pathSeparator}packages');
  }

  static String _resolveLocalPackageFileName(Uri assetDownloadUri) {
    final rawName = assetDownloadUri.pathSegments.isEmpty
        ? ''
        : assetDownloadUri.pathSegments.last.trim();
    final normalized = Uri.decodeComponent(rawName);
    final fallback =
        'secondloop-update-${DateTime.now().millisecondsSinceEpoch}.nupkg';
    final source = normalized.isEmpty ? fallback : normalized;
    final sanitized = source.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (sanitized.isEmpty) {
      return fallback;
    }
    return sanitized;
  }

  static Future<void> _downloadAssetToFile(Uri uri, File destination) async {
    if (destination.existsSync()) {
      await destination.delete();
    }
    if (uri.scheme == 'file') {
      final sourcePath = uri.toFilePath();
      await File(sourcePath).copy(destination.path);
      return;
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'windows_velopack_stage_failed_http_${response.statusCode}');
      }

      final sink = destination.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  static void _deletePendingPackageUpdates(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    final packagesDir = Directory(
      '$appRoot${Platform.pathSeparator}packages',
    );
    if (!packagesDir.existsSync()) {
      return;
    }

    for (final entity in packagesDir.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      final version = _extractVersionFromNupkgName(fileName);
      if (version == null) continue;
      if (currentVersion != null &&
          _compareVersionStrings(version, currentVersion) <= 0) {
        continue;
      }
      try {
        entity.deleteSync();
      } catch (_) {}
    }
  }

  static bool _hasPendingPackageUpdate(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    if (currentVersion == null) {
      return false;
    }

    final pendingVersion = _readNewestPackageVersion(appRoot);
    if (pendingVersion == null) {
      return false;
    }

    return _compareVersionStrings(pendingVersion, currentVersion) > 0;
  }

  static String? _readCurrentInstalledVersion(String appRootPath) {
    final sqVersionPath = File(
      '$appRootPath${Platform.pathSeparator}current${Platform.pathSeparator}sq.version',
    );
    if (!sqVersionPath.existsSync()) {
      return null;
    }

    try {
      final content = sqVersionPath.readAsStringSync();
      final match = RegExp(
        r'<version>\s*([^<]+)\s*</version>',
        caseSensitive: false,
      ).firstMatch(content);
      final version = match?.group(1)?.trim();
      if (version == null || version.isEmpty) {
        return null;
      }
      return version;
    } catch (_) {
      return null;
    }
  }

  static String? _readNewestPackageVersion(String appRootPath) {
    final packagesDir = Directory(
      '$appRootPath${Platform.pathSeparator}packages',
    );
    if (!packagesDir.existsSync()) {
      return null;
    }

    String? newestVersion;
    for (final entity in packagesDir.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      final version = _extractVersionFromNupkgName(fileName);
      if (version == null) continue;
      if (newestVersion == null ||
          _compareVersionStrings(version, newestVersion) > 0) {
        newestVersion = version;
      }
    }

    return newestVersion;
  }

  static String? _extractVersionFromNupkgName(String fileName) {
    final normalized = fileName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (!lower.endsWith('.nupkg') || lower.endsWith('.snupkg')) {
      return null;
    }

    final match = RegExp(
      r'^.+-(.+)-full\.nupkg$',
      caseSensitive: false,
    ).firstMatch(normalized);
    final version = match?.group(1)?.trim();
    if (version == null || version.isEmpty) {
      return null;
    }
    return version;
  }

  static int _compareVersionStrings(String left, String right) {
    final leftParts = _parseVersionSegments(left);
    final rightParts = _parseVersionSegments(right);
    if (leftParts.isEmpty || rightParts.isEmpty) {
      return left.compareTo(right);
    }

    final comparedLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < comparedLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }

  static List<int> _parseVersionSegments(String input) {
    final matches = RegExp(r'\d+').allMatches(input.trim());
    if (matches.isEmpty) {
      return const [];
    }

    final segments = <int>[];
    for (final match in matches) {
      final parsed = int.tryParse(match.group(0) ?? '');
      if (parsed == null) continue;
      segments.add(parsed);
      if (segments.length >= 8) {
        break;
      }
    }
    return segments;
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(
      executable,
      arguments,
      mode: mode,
    );
  }
}
