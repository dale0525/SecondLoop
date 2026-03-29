import 'dart:io';

import '../app_update_models.dart';
import '../app_update_helpers.dart';
import 'velopack_paths.dart';

typedef VelopackProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

typedef VelopackNowProvider = DateTime Function();
typedef VelopackProcessProbe = VelopackProcessProbeStatus Function(
  int pid, {
  required String expectedExecutablePath,
});

VelopackProcessProbeStatus interpretWindowsProcessQueryResult({
  required int exitCode,
  required String stdoutText,
  required String expectedExecutablePath,
}) {
  if (exitCode != 0) {
    return VelopackProcessProbeStatus.unknown;
  }

  final outputLine =
      stdoutText.split(RegExp(r'\r?\n')).map((line) => line.trim()).firstWhere(
            (line) => line.isNotEmpty,
            orElse: () => '',
          );
  if (outputLine.isEmpty || outputLine == '__MISSING__') {
    return VelopackProcessProbeStatus.notRunning;
  }

  final fields = outputLine.split('\t');
  final executablePath = fields.isEmpty ? '' : fields.first.trim();
  final processName = fields.length < 2 ? '' : fields[1].trim();
  final normalizedExpectedPath =
      VelopackUpdateClient._normalizePathForComparison(expectedExecutablePath);

  if (executablePath.isNotEmpty) {
    return VelopackUpdateClient._normalizePathForComparison(executablePath) ==
            normalizedExpectedPath
        ? VelopackProcessProbeStatus.runningExpectedProcess
        : VelopackProcessProbeStatus.notRunning;
  }

  if (processName.isNotEmpty) {
    final expectedName = expectedExecutablePath
        .split(RegExp(r'[\\/]'))
        .last
        .trim()
        .toLowerCase();
    return processName.toLowerCase() == expectedName
        ? VelopackProcessProbeStatus.runningExpectedProcess
        : VelopackProcessProbeStatus.notRunning;
  }

  return VelopackProcessProbeStatus.unknown;
}

abstract class WindowsStagedUpdateClient {
  bool isAvailable();

  bool hasPendingUpdate();

  String? pendingUpdateVersion();

  String? pendingUpdatePackagePath();

  Future<void> stageAsset(Uri assetDownloadUri);

  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  });

  Future<PendingUpdateStartupResult> applyPendingOnStartup({
    required int waitPid,
  });

  Future<void> applyPendingAndRestart({
    required int waitPid,
  });
}

class VelopackUpdateClient implements WindowsStagedUpdateClient {
  static const _pendingApplyAttemptFileName = '.secondloop_pending_apply';
  static const _pendingApplyRetryGracePeriod = Duration(minutes: 5);

  VelopackUpdateClient({
    String? updateExecutablePath,
    VelopackProcessStarter? processStarter,
    VelopackNowProvider? now,
    VelopackProcessProbe? processProbe,
  })  : _updateExecutablePath = updateExecutablePath,
        _processStarter = processStarter ?? _defaultProcessStarter,
        _now = now ?? DateTime.now,
        _processProbe = processProbe ?? _probeProcessStatus;

  final String? _updateExecutablePath;
  final VelopackProcessStarter _processStarter;
  final VelopackNowProvider _now;
  final VelopackProcessProbe _processProbe;

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
  String? pendingUpdateVersion() {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      return null;
    }
    final appRoot = File(updateExePath).absolute.parent.path;
    return _readNewestPackageVersion(appRoot);
  }

  @override
  String? pendingUpdatePackagePath() {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      return null;
    }
    final appRoot = File(updateExePath).absolute.parent.path;
    return _readNewestPackageFile(appRoot)?.path;
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
  Future<PendingUpdateStartupResult> applyPendingOnStartup({
    required int waitPid,
  }) async {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      throw StateError('windows_velopack_unavailable');
    }

    final appRoot = File(updateExePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    if (currentVersion == null) {
      return const PendingUpdateStartupResult.noPendingUpdate();
    }

    final pendingVersion = _readNewestPackageVersion(appRoot);
    final pendingAttemptResult = _resolvePendingApplyAttempt(
      updateExecutablePath: updateExePath,
      currentVersion: currentVersion,
      pendingVersion: pendingVersion,
      throwIfAttemptInProgress: false,
    );
    if (pendingAttemptResult != null) {
      return pendingAttemptResult;
    }

    if (pendingVersion == null ||
        _compareVersionStrings(pendingVersion, currentVersion) <= 0) {
      return const PendingUpdateStartupResult.noPendingUpdate();
    }

    await _startDetachedApply(
      updateExecutablePath: updateExePath,
      waitPid: waitPid,
      pendingVersion: pendingVersion,
    );
    return const PendingUpdateStartupResult.updateDispatched();
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

    _resolvePendingApplyAttempt(
      updateExecutablePath: updateExePath,
      currentVersion: currentVersion,
      pendingVersion: pendingVersion,
      throwIfAttemptInProgress: true,
    );

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
    try {
      final process = await _processStarter(
        updateExecutablePath,
        _buildApplyArguments(waitPid: waitPid, packagePath: packagePath),
        mode: ProcessStartMode.detached,
      );
      if (pendingVersion != null && pendingVersion.isNotEmpty) {
        _writePendingApplyAttempt(
          updateExecutablePath,
          _PendingApplyAttempt(
            version: pendingVersion,
            startedAtUtc: _now().toUtc(),
            updaterPid: process.pid,
          ),
        );
      }
    } catch (_) {
      _clearPendingApplyAttempt(updateExecutablePath);
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
    if (uri.scheme == 'file') {
      final sourcePath = File(uri.toFilePath()).absolute.path;
      final destinationPath = destination.absolute.path;
      if (_normalizePathForComparison(sourcePath) ==
          _normalizePathForComparison(destinationPath)) {
        return;
      }
      if (destination.existsSync()) {
        await destination.delete();
      }
      await File(sourcePath).copy(destination.path);
      return;
    }

    if (destination.existsSync()) {
      await destination.delete();
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

  PendingUpdateStartupResult? _resolvePendingApplyAttempt({
    required String updateExecutablePath,
    required String currentVersion,
    required String? pendingVersion,
    required bool throwIfAttemptInProgress,
  }) {
    final attempt = _readPendingApplyAttempt(updateExecutablePath);
    if (attempt == null) {
      return null;
    }

    final attemptIsStale = pendingVersion == null ||
        !sameNormalizedVersion(pendingVersion, attempt.version) ||
        _compareVersionStrings(currentVersion, attempt.version) >= 0;
    if (attemptIsStale) {
      _clearPendingApplyAttempt(updateExecutablePath);
      return null;
    }

    if (attempt.updaterPid == null) {
      _clearPendingApplyAttempt(updateExecutablePath);
      return null;
    }

    final startedAtUtc = attempt.startedAtUtc;
    if (startedAtUtc != null &&
        _now().toUtc().difference(startedAtUtc) <
            _pendingApplyRetryGracePeriod) {
      final processStatus = _processProbe(
        attempt.updaterPid!,
        expectedExecutablePath: updateExecutablePath,
      );
      if (processStatus == VelopackProcessProbeStatus.notRunning) {
        _deletePendingPackageUpdates(updateExecutablePath);
        _clearPendingApplyAttempt(updateExecutablePath);
        throw StateError(
            'windows_velopack_previous_apply_failed_${attempt.version}');
      }
      if (processStatus == VelopackProcessProbeStatus.unknown) {
        if (throwIfAttemptInProgress) {
          throw StateError(
            'windows_velopack_apply_already_in_progress_${attempt.version}',
          );
        }
        return const PendingUpdateStartupResult.updateInProgress();
      }
      if (throwIfAttemptInProgress) {
        throw StateError(
          'windows_velopack_apply_already_in_progress_${attempt.version}',
        );
      }
      return const PendingUpdateStartupResult.updateInProgress();
    }

    _deletePendingPackageUpdates(
      updateExecutablePath,
      targetVersion: attempt.version,
    );
    _clearPendingApplyAttempt(updateExecutablePath);
    throw StateError(
        'windows_velopack_previous_apply_failed_${attempt.version}');
  }

  static File _pendingApplyAttemptFile(String updateExecutablePath) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    return File(
      '$appRoot${Platform.pathSeparator}packages${Platform.pathSeparator}$_pendingApplyAttemptFileName',
    );
  }

  static _PendingApplyAttempt? _readPendingApplyAttempt(
      String updateExecutablePath) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    if (!markerFile.existsSync()) {
      return null;
    }

    try {
      final content = markerFile.readAsStringSync().trim();
      if (content.isEmpty) {
        return null;
      }
      final lines = content
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (lines.isEmpty) {
        return null;
      }

      final version = lines.first;
      final startedAtUtc =
          lines.length < 2 ? null : DateTime.tryParse(lines[1])?.toUtc();
      final updaterPid = lines.length < 3 ? null : int.tryParse(lines[2]);
      return _PendingApplyAttempt(
        version: version,
        startedAtUtc: startedAtUtc,
        updaterPid: updaterPid,
      );
    } catch (_) {
      return null;
    }
  }

  static void _writePendingApplyAttempt(
    String updateExecutablePath,
    _PendingApplyAttempt attempt,
  ) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    markerFile.parent.createSync(recursive: true);
    final lines = <String>[attempt.version];
    if (attempt.startedAtUtc != null) {
      lines.add(attempt.startedAtUtc!.toIso8601String());
    }
    if (attempt.updaterPid != null) {
      lines.add(attempt.updaterPid!.toString());
    }
    markerFile.writeAsStringSync(lines.join('\n'));
  }

  static VelopackProcessProbeStatus _probeProcessStatus(
    int pid, {
    required String expectedExecutablePath,
  }) {
    if (pid <= 0) {
      return VelopackProcessProbeStatus.notRunning;
    }

    try {
      if (Platform.isWindows) {
        const shellCandidates = <String>['powershell.exe', 'pwsh.exe'];
        for (final shell in shellCandidates) {
          try {
            final result = Process.runSync(
              shell,
              [
                '-NoProfile',
                '-Command',
                "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId = $pid' -ErrorAction SilentlyContinue; if (-not \$p) { Write-Output '__MISSING__'; exit 0 }; \$path = if (\$p.ExecutablePath) { [string]\$p.ExecutablePath } else { '' }; \$name = if (\$p.Name) { [string]\$p.Name } else { '' }; Write-Output (\$path + \"`t\" + \$name)",
              ],
            );
            return interpretWindowsProcessQueryResult(
              exitCode: result.exitCode,
              stdoutText: '${result.stdout}',
              expectedExecutablePath: expectedExecutablePath,
            );
          } catch (_) {
            continue;
          }
        }
        return VelopackProcessProbeStatus.unknown;
      }

      final result = Process.runSync('kill', ['-0', pid.toString()]);
      return result.exitCode == 0
          ? VelopackProcessProbeStatus.runningExpectedProcess
          : VelopackProcessProbeStatus.notRunning;
    } catch (_) {
      return VelopackProcessProbeStatus.unknown;
    }
  }

  static void _clearPendingApplyAttempt(String updateExecutablePath) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    if (!markerFile.existsSync()) {
      return;
    }
    try {
      markerFile.deleteSync();
    } catch (_) {}
  }

  static void _deletePendingPackageUpdates(
    String updateExecutablePath, {
    String? targetVersion,
  }) {
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
      if (version == null) {
        continue;
      }
      if (targetVersion != null &&
          !sameNormalizedVersion(version, targetVersion)) {
        continue;
      }
      if (_compareVersionStrings(version, currentVersion) <= 0) {
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
    final newestPackage = _readNewestPackageFile(appRootPath);
    if (newestPackage == null) {
      return null;
    }
    final fileName = newestPackage.uri.pathSegments.isEmpty
        ? ''
        : newestPackage.uri.pathSegments.last;
    return _extractVersionFromNupkgName(fileName);
  }

  static File? _readNewestPackageFile(String appRootPath) {
    final packagesDir = Directory(
      '$appRootPath${Platform.pathSeparator}packages',
    );
    if (!packagesDir.existsSync()) {
      return null;
    }

    File? newestPackage;
    String? newestVersion;
    for (final entity in packagesDir.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      if (!isWindowsVelopackPackageName(fileName)) {
        continue;
      }
      final version = _extractVersionFromNupkgName(fileName);
      if (version == null) continue;
      if (newestVersion == null ||
          _compareVersionStrings(version, newestVersion) > 0) {
        newestPackage = entity;
        newestVersion = version;
      }
    }

    return newestPackage;
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
      r'^.+-((?:\d+\.){2,7}\d+(?:-[0-9A-Za-z.-]+)?)-full\.nupkg$',
      caseSensitive: false,
    ).firstMatch(normalized);
    final version = match?.group(1)?.trim();
    if (version == null || version.isEmpty) {
      return null;
    }
    return version;
  }

  static int _compareVersionStrings(String left, String right) {
    final compared = compareReleaseTagWithCurrentVersion(left, right);
    if (parseComparableAppVersion(left) != null &&
        parseComparableAppVersion(right) != null) {
      return compared;
    }

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

  static String _normalizePathForComparison(String value) {
    return value.replaceAll('\\', '/').toLowerCase();
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

enum VelopackProcessProbeStatus {
  runningExpectedProcess,
  notRunning,
  unknown,
}

class _PendingApplyAttempt {
  const _PendingApplyAttempt({
    required this.version,
    this.startedAtUtc,
    this.updaterPid,
  });

  final String version;
  final DateTime? startedAtUtc;
  final int? updaterPid;
}
