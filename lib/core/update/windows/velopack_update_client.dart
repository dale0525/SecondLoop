import 'dart:io';

import 'velopack_paths.dart';

typedef VelopackProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

abstract class WindowsStagedUpdateClient {
  bool isAvailable();

  bool hasPendingUpdate();

  Future<void> stageAsset(Uri assetDownloadUri);

  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  });

  Future<bool> applyPendingOnStartup({
    required int waitPid,
  });

  Future<void> applyPendingAndRestart({
    required int waitPid,
  });
}

class VelopackUpdateClient implements WindowsStagedUpdateClient {
  static const _pendingApplyAttemptFileName = '.secondloop_pending_apply';

  VelopackUpdateClient({
    String? updateExecutablePath,
    VelopackProcessStarter? processStarter,
  })  : _updateExecutablePath = updateExecutablePath,
        _processStarter = processStarter ?? _defaultProcessStarter;

  final String? _updateExecutablePath;
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
  bool hasPendingUpdate() {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      return false;
    }
    return _hasPendingPackageUpdate(updateExePath);
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
    await _startDetachedApply(
      updateExecutablePath: _updateExePath,
      waitPid: waitPid,
      packagePath: packageFile.path,
      pendingVersion:
          _extractVersionFromNupkgName(packageFile.uri.pathSegments.last),
    );
  }

  @override
  Future<bool> applyPendingOnStartup({
    required int waitPid,
  }) async {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      throw StateError('windows_velopack_unavailable');
    }

    final appRoot = File(updateExePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    if (currentVersion == null) {
      return false;
    }

    final pendingVersion = _readNewestPackageVersion(appRoot);
    _resolvePendingApplyAttempt(
      updateExecutablePath: updateExePath,
      currentVersion: currentVersion,
      pendingVersion: pendingVersion,
    );

    if (pendingVersion == null ||
        _compareVersionStrings(pendingVersion, currentVersion) <= 0) {
      return false;
    }

    await _startDetachedApply(
      updateExecutablePath: updateExePath,
      waitPid: waitPid,
      pendingVersion: pendingVersion,
    );
    return true;
  }

  @override
  Future<void> applyPendingAndRestart({
    required int waitPid,
  }) async {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      throw StateError('windows_velopack_unavailable');
    }

    final appRoot = File(updateExePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    final pendingVersion = _readNewestPackageVersion(appRoot);

    if (currentVersion == null ||
        pendingVersion == null ||
        _compareVersionStrings(pendingVersion, currentVersion) <= 0) {
      throw StateError('windows_velopack_no_pending_update');
    }

    await _startDetachedApply(
      updateExecutablePath: updateExePath,
      waitPid: waitPid,
      pendingVersion: pendingVersion,
    );
  }

  Future<void> _startDetachedApply({
    required String updateExecutablePath,
    required int waitPid,
    required String? pendingVersion,
    String? packagePath,
  }) async {
    if (pendingVersion != null && pendingVersion.isNotEmpty) {
      _writePendingApplyAttemptVersion(updateExecutablePath, pendingVersion);
    }
    try {
      await _processStarter(
        updateExecutablePath,
        _buildApplyArguments(waitPid: waitPid, packagePath: packagePath),
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      _clearPendingApplyAttemptVersion(updateExecutablePath);
      rethrow;
    }
  }

  static List<String> _buildApplyArguments({
    required int waitPid,
    String? packagePath,
  }) {
    final arguments = <String>[
      'apply',
      '--silent',
      '--restart',
      '--waitPid',
      waitPid.toString(),
    ];
    if (packagePath != null) {
      arguments
        ..add('--package')
        ..add(packagePath);
    }
    return arguments;
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

  static void _resolvePendingApplyAttempt({
    required String updateExecutablePath,
    required String currentVersion,
    required String? pendingVersion,
  }) {
    final attemptedVersion =
        _readPendingApplyAttemptVersion(updateExecutablePath);
    if (attemptedVersion == null) {
      return;
    }

    final attemptIsStale = pendingVersion == null ||
        pendingVersion != attemptedVersion ||
        _compareVersionStrings(currentVersion, attemptedVersion) >= 0;
    if (attemptIsStale) {
      _clearPendingApplyAttemptVersion(updateExecutablePath);
      return;
    }

    _deletePendingPackageUpdates(updateExecutablePath);
    _clearPendingApplyAttemptVersion(updateExecutablePath);
    throw StateError(
        'windows_velopack_previous_apply_failed_$attemptedVersion');
  }

  static File _pendingApplyAttemptFile(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    return File(
      '$appRoot${Platform.pathSeparator}packages${Platform.pathSeparator}$_pendingApplyAttemptFileName',
    );
  }

  static String? _readPendingApplyAttemptVersion(String updateExecutablePath) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    if (!markerFile.existsSync()) {
      return null;
    }

    try {
      final version = markerFile.readAsStringSync().trim();
      if (version.isEmpty) {
        return null;
      }
      return version;
    } catch (_) {
      return null;
    }
  }

  static void _writePendingApplyAttemptVersion(
    String updateExecutablePath,
    String version,
  ) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    markerFile.parent.createSync(recursive: true);
    markerFile.writeAsStringSync(version);
  }

  static void _clearPendingApplyAttemptVersion(String updateExecutablePath) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    if (!markerFile.existsSync()) {
      return;
    }
    try {
      markerFile.deleteSync();
    } catch (_) {}
  }

  static void _deletePendingPackageUpdates(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    if (currentVersion == null) {
      return;
    }

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
      if (version == null ||
          _compareVersionStrings(version, currentVersion) <= 0) {
        continue;
      }
      try {
        entity.deleteSync();
      } catch (_) {}
    }
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
