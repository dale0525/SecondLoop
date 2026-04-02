import 'dart:io';

import '../app_update_models.dart';
import '../app_update_helpers.dart';
import 'velopack_paths.dart';

typedef VelopackProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});
typedef VelopackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef VelopackNowProvider = DateTime Function();
typedef VelopackProcessProbe = Future<VelopackProcessProbeStatus> Function(
  int pid, {
  required String expectedExecutablePath,
});
typedef PendingApplyAttemptWriter = void Function(
  String updateExecutablePath, {
  required String version,
  DateTime? startedAtUtc,
  int? updaterPid,
});

const _windowsProcessProbeShellCandidates = <String>[
  'powershell.exe',
  'pwsh.exe',
];
const _defaultWindowsChannel = 'win';

const _defaultWindowsVelopackAppId = String.fromEnvironment(
  'SECONDLOOP_APP_ID',
  defaultValue: 'com.secondloop.secondloop',
);

List<String> buildWindowsProcessProbeCommandArguments(int pid) {
  final command =
      "\$p = Get-CimInstance Win32_Process -Filter \"ProcessId = $pid\" -ErrorAction SilentlyContinue; if (-not \$p) { Write-Output '__MISSING__'; exit 0 }; \$path = if (\$p.ExecutablePath) { [string]\$p.ExecutablePath } else { '' }; \$name = if (\$p.Name) { [string]\$p.Name } else { '' }; Write-Output (\$path + \"`t\" + \$name)";
  return ['-NoProfile', '-Command', command];
}

Future<VelopackProcessProbeStatus> probeWindowsProcessStatusForTest(
  int pid, {
  required String expectedExecutablePath,
  required VelopackProcessRunner processRunner,
  List<String> shellCandidates = _windowsProcessProbeShellCandidates,
}) {
  return VelopackUpdateClient._probeProcessStatus(
    pid,
    expectedExecutablePath: expectedExecutablePath,
    processRunner: processRunner,
    shellCandidates: shellCandidates,
    isWindowsOverride: true,
  );
}

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
  final expectedName =
      expectedExecutablePath.split(RegExp(r'[\\/]')).last.trim().toLowerCase();
  final normalizedExpectedPath =
      VelopackUpdateClient._normalizePathForComparison(expectedExecutablePath);

  if (executablePath.isNotEmpty) {
    if (!executablePath.contains(RegExp(r'[\\/]')) &&
        executablePath.trim().toLowerCase() == expectedName) {
      return VelopackProcessProbeStatus.unknown;
    }
    return VelopackUpdateClient._normalizePathForComparison(executablePath) ==
            normalizedExpectedPath
        ? VelopackProcessProbeStatus.runningExpectedProcess
        : VelopackProcessProbeStatus.notRunning;
  }

  if (processName.isNotEmpty) {
    return VelopackProcessProbeStatus.unknown;
  }

  return VelopackProcessProbeStatus.unknown;
}

abstract class WindowsStagedUpdateClient {
  String get appId;

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
    String? appId,
    VelopackProcessStarter? processStarter,
    VelopackNowProvider? now,
    VelopackProcessRunner? processRunner,
    VelopackProcessProbe? processProbe,
    PendingApplyAttemptWriter? pendingApplyAttemptWriter,
  })  : _updateExecutablePath = updateExecutablePath,
        _appId = appId,
        _processStarter = processStarter ?? _defaultProcessStarter,
        _now = now ?? DateTime.now,
        _pendingApplyAttemptWriter =
            pendingApplyAttemptWriter ?? _writePendingApplyAttempt,
        _processProbe = processProbe ??
            ((pid, {required expectedExecutablePath}) => _probeProcessStatus(
                  pid,
                  expectedExecutablePath: expectedExecutablePath,
                  processRunner: processRunner ?? _defaultProcessRunner,
                ));

  final String? _updateExecutablePath;
  final String? _appId;
  final VelopackProcessStarter _processStarter;
  final VelopackNowProvider _now;
  final PendingApplyAttemptWriter _pendingApplyAttemptWriter;
  final VelopackProcessProbe _processProbe;

  String get _updateExePath =>
      _updateExecutablePath ?? resolveVelopackUpdateExePath();
  String get _resolvedAppId {
    final configured = _appId?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return _defaultWindowsVelopackAppId;
  }

  @override
  String get appId => _resolvedAppId;

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
    return _hasPendingPackageUpdate(updateExePath, appId: _resolvedAppId);
  }

  @override
  String? pendingUpdateVersion() {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      return null;
    }
    final appRoot = File(updateExePath).absolute.parent.path;
    return _readNewestPackageVersion(appRoot, appId: _resolvedAppId);
  }

  @override
  String? pendingUpdatePackagePath() {
    final updateExePath = _updateExePath;
    if (!File(updateExePath).existsSync()) {
      return null;
    }
    final appRoot = File(updateExePath).absolute.parent.path;
    return _readNewestPackageFile(appRoot, appId: _resolvedAppId)?.path;
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
      pendingVersion: _extractVersionFromNupkgName(
        packageFile.uri.pathSegments.last,
        appId: _resolvedAppId,
        channels: _detectInstalledChannels(
          File(_updateExePath).absolute.parent.path,
        ),
      ),
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

    final pendingVersion =
        _readNewestPackageVersion(appRoot, appId: _resolvedAppId);
    final pendingAttemptResult = await _resolvePendingApplyAttempt(
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
    final pendingVersion =
        _readNewestPackageVersion(appRoot, appId: _resolvedAppId);

    if (currentVersion == null ||
        pendingVersion == null ||
        _compareVersionStrings(pendingVersion, currentVersion) <= 0) {
      throw StateError('windows_velopack_no_pending_update');
    }

    await _resolvePendingApplyAttempt(
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
        try {
          _pendingApplyAttemptWriter(
            updateExecutablePath,
            version: pendingVersion,
            startedAtUtc: _now().toUtc(),
            updaterPid: process.pid,
          );
        } catch (_) {}
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
    _ensureChannelMetadataForStagedPackage(
      updateExecutablePath: updateExePath,
      packageFileName: packageFile.uri.pathSegments.last,
      appId: _resolvedAppId,
    );
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

  static bool _hasPendingPackageUpdate(
    String updateExecutablePath, {
    required String appId,
  }) {
    final appRoot = File(updateExecutablePath).absolute.parent.path;
    final currentVersion = _readCurrentInstalledVersion(appRoot);
    if (currentVersion == null) {
      return false;
    }

    final pendingVersion = _readNewestPackageVersion(appRoot, appId: appId);
    if (pendingVersion == null) {
      return false;
    }

    return _compareVersionStrings(pendingVersion, currentVersion) > 0;
  }

  Future<PendingUpdateStartupResult?> _resolvePendingApplyAttempt({
    required String updateExecutablePath,
    required String currentVersion,
    required String? pendingVersion,
    required bool throwIfAttemptInProgress,
  }) async {
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
      final processStatus = await _processProbe(
        attempt.updaterPid!,
        expectedExecutablePath: updateExecutablePath,
      );
      if (processStatus == VelopackProcessProbeStatus.notRunning) {
        _deletePendingPackageUpdates(
          updateExecutablePath,
          targetVersion: attempt.version,
          appId: _resolvedAppId,
        );
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
        return const PendingUpdateStartupResult.probeInconclusive();
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
      appId: _resolvedAppId,
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
    String updateExecutablePath, {
    required String version,
    DateTime? startedAtUtc,
    int? updaterPid,
  }) {
    final markerFile = _pendingApplyAttemptFile(updateExecutablePath);
    markerFile.parent.createSync(recursive: true);
    final lines = <String>[version];
    if (startedAtUtc != null) {
      lines.add(startedAtUtc.toIso8601String());
    }
    if (updaterPid != null) {
      lines.add(updaterPid.toString());
    }
    markerFile.writeAsStringSync(lines.join('\n'));
  }

  static Future<VelopackProcessProbeStatus> _probeProcessStatus(
    int pid, {
    required String expectedExecutablePath,
    required VelopackProcessRunner processRunner,
    List<String> shellCandidates = _windowsProcessProbeShellCandidates,
    bool? isWindowsOverride,
  }) async {
    if (pid <= 0) {
      return VelopackProcessProbeStatus.notRunning;
    }

    try {
      final isWindowsPlatform = isWindowsOverride ?? Platform.isWindows;
      if (isWindowsPlatform) {
        for (final shell in shellCandidates) {
          try {
            final result = await processRunner(
              shell,
              buildWindowsProcessProbeCommandArguments(pid),
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

      final result = await processRunner('kill', ['-0', pid.toString()]);
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
    required String appId,
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

    final channels = _detectInstalledChannels(appRoot);
    for (final entity in packagesDir.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      if (!isWindowsVelopackPackageNameForApp(fileName, appId: appId)) {
        continue;
      }
      final version = _extractVersionFromNupkgName(
        fileName,
        appId: appId,
        channels: channels,
      );
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

  static String? _readNewestPackageVersion(
    String appRootPath, {
    required String appId,
  }) {
    final newestPackage = _readNewestPackageFile(appRootPath, appId: appId);
    if (newestPackage == null) {
      return null;
    }
    final fileName = newestPackage.uri.pathSegments.isEmpty
        ? ''
        : newestPackage.uri.pathSegments.last;
    return _extractVersionFromNupkgName(
      fileName,
      appId: appId,
      channels: _detectInstalledChannels(appRootPath),
    );
  }

  static File? _readNewestPackageFile(
    String appRootPath, {
    required String appId,
  }) {
    final packagesDir = Directory(
      '$appRootPath${Platform.pathSeparator}packages',
    );
    if (!packagesDir.existsSync()) {
      return null;
    }

    final channels = _detectInstalledChannels(appRootPath);
    File? newestPackage;
    String? newestVersion;
    int? newestTieBreaker;
    String? newestPackageName;
    for (final entity in packagesDir.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      if (!isWindowsVelopackPackageNameForApp(fileName, appId: appId)) {
        continue;
      }
      final version = _extractVersionFromNupkgName(
        fileName,
        appId: appId,
        channels: channels,
      );
      if (version == null) continue;
      final tieBreaker = _pendingPackageSelectionTieBreaker(
        fileName,
        appId: appId,
        installedChannels: channels,
      );
      if (newestVersion == null ||
          _compareVersionStrings(version, newestVersion) > 0 ||
          (_compareVersionStrings(version, newestVersion) == 0 &&
              (newestTieBreaker == null ||
                  tieBreaker < newestTieBreaker ||
                  (tieBreaker == newestTieBreaker &&
                      (newestPackageName == null ||
                          fileName.toLowerCase().compareTo(
                                    newestPackageName.toLowerCase(),
                                  ) <
                              0))))) {
        newestPackage = entity;
        newestVersion = version;
        newestTieBreaker = tieBreaker;
        newestPackageName = fileName;
      }
    }

    return newestPackage;
  }

  static int _pendingPackageSelectionTieBreaker(
    String fileName, {
    required String appId,
    required List<String> installedChannels,
  }) {
    final normalizedInstalledChannels = installedChannels
        .map((channel) => channel.trim().toLowerCase())
        .where((channel) => channel.isNotEmpty)
        .toSet();
    final packageChannel = _extractChannelFromNupkgName(
      fileName,
      appId: appId,
    );
    if (packageChannel != null &&
        normalizedInstalledChannels.contains(packageChannel)) {
      return 0;
    }
    if (packageChannel == _defaultWindowsChannel) {
      return 1;
    }
    if (packageChannel == null) {
      return normalizedInstalledChannels.contains(_defaultWindowsChannel)
          ? 2
          : 1;
    }
    return 3;
  }

  static String? _extractVersionFromNupkgName(
    String fileName, {
    required String appId,
    Iterable<String> channels = const <String>[],
  }) {
    final normalized = fileName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (!lower.endsWith('.nupkg') || lower.endsWith('.snupkg')) {
      return null;
    }

    if (!isWindowsVelopackPackageNameForApp(normalized, appId: appId)) {
      return null;
    }

    final prefix = '${appId.trim()}-';
    final packageStem = normalized.substring(
      prefix.length,
      normalized.length - '.nupkg'.length,
    );
    if (!packageStem.toLowerCase().endsWith('-full')) {
      return null;
    }

    final versionWithOptionalChannel =
        packageStem.substring(0, packageStem.length - '-full'.length);
    if (parseComparableAppVersion(versionWithOptionalChannel) != null) {
      return versionWithOptionalChannel;
    }

    final firstDashIndex = versionWithOptionalChannel.indexOf('-');
    if (firstDashIndex > 0 &&
        firstDashIndex < versionWithOptionalChannel.length - 1) {
      final versionPrefix =
          versionWithOptionalChannel.substring(0, firstDashIndex);
      final channelSuffix =
          versionWithOptionalChannel.substring(firstDashIndex + 1).trim();
      final looksLikeSimpleChannel =
          RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(channelSuffix);
      if (channelSuffix.isNotEmpty &&
          looksLikeSimpleChannel &&
          parseComparableAppVersion(versionPrefix) != null) {
        final normalizedChannelSuffix = channelSuffix.toLowerCase();
        if (channels.isEmpty) {
          return normalizedChannelSuffix == _defaultWindowsChannel
              ? versionPrefix
              : null;
        }

        final knownChannels = channels
            .map((channel) => channel.trim().toLowerCase())
            .where((channel) => channel.isNotEmpty)
            .toSet();
        if (knownChannels.contains(normalizedChannelSuffix)) {
          return versionPrefix;
        }
        return null;
      }
    }

    final knownChannels = channels
        .map((channel) => channel.trim())
        .where((channel) => channel.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((left, right) => right.length.compareTo(left.length));
    final normalizedVersionWithOptionalChannel =
        versionWithOptionalChannel.toLowerCase();
    for (final channel in knownChannels) {
      final suffix = '-${channel.toLowerCase()}';
      if (!normalizedVersionWithOptionalChannel.endsWith(suffix) ||
          versionWithOptionalChannel.length <= suffix.length) {
        continue;
      }

      final strippedVersion = versionWithOptionalChannel.substring(
        0,
        versionWithOptionalChannel.length - suffix.length,
      );
      if (parseComparableAppVersion(strippedVersion) != null) {
        return strippedVersion;
      }
    }

    return null;
  }

  static List<String> _detectInstalledChannels(String appRootPath) {
    final appRoot = Directory(appRootPath);
    if (!appRoot.existsSync()) {
      return const <String>[];
    }

    final channels = <String>{};
    for (final entity in appRoot.listSync()) {
      if (entity is! File) continue;
      final fileName =
          entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
      final releasesMatch = RegExp(
        r'^releases\.(.+)\.json$',
        caseSensitive: false,
      ).firstMatch(fileName);
      final assetsMatch = RegExp(
        r'^assets\.(.+)\.json$',
        caseSensitive: false,
      ).firstMatch(fileName);
      final channel = releasesMatch?.group(1)?.trim() ??
          assetsMatch?.group(1)?.trim() ??
          '';
      if (channel.isNotEmpty) {
        channels.add(channel);
      }
    }
    return channels.toList(growable: false);
  }

  static void _ensureChannelMetadataForStagedPackage({
    required String updateExecutablePath,
    required String packageFileName,
    required String appId,
  }) {
    final channel = _extractChannelFromNupkgName(
      packageFileName,
      appId: appId,
    );
    if (channel == null || channel == _defaultWindowsChannel) {
      return;
    }

    final appRoot = File(updateExecutablePath).absolute.parent.path;
    final releasesMetadataFile = File(
      '$appRoot${Platform.pathSeparator}releases.$channel.json',
    );
    if (releasesMetadataFile.existsSync()) {
      return;
    }

    try {
      releasesMetadataFile.writeAsStringSync('{}');
    } catch (_) {}
  }

  static String? _extractChannelFromNupkgName(
    String fileName, {
    required String appId,
  }) {
    final normalized = fileName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (!lower.endsWith('.nupkg') || lower.endsWith('.snupkg')) {
      return null;
    }

    if (!isWindowsVelopackPackageNameForApp(normalized, appId: appId)) {
      return null;
    }

    final prefix = '${appId.trim()}-';
    final packageStem = normalized.substring(
      prefix.length,
      normalized.length - '.nupkg'.length,
    );
    if (!packageStem.toLowerCase().endsWith('-full')) {
      return null;
    }

    final versionWithOptionalChannel =
        packageStem.substring(0, packageStem.length - '-full'.length);
    if (parseComparableAppVersion(versionWithOptionalChannel) != null) {
      return null;
    }

    final firstDashIndex = versionWithOptionalChannel.indexOf('-');
    if (firstDashIndex <= 0 ||
        firstDashIndex >= versionWithOptionalChannel.length - 1) {
      return null;
    }

    final versionPrefix =
        versionWithOptionalChannel.substring(0, firstDashIndex);
    final channelSuffix =
        versionWithOptionalChannel.substring(firstDashIndex + 1).trim();
    final looksLikeSimpleChannel =
        RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(channelSuffix);
    if (channelSuffix.isEmpty ||
        !looksLikeSimpleChannel ||
        parseComparableAppVersion(versionPrefix) == null) {
      return null;
    }

    return channelSuffix.toLowerCase();
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

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
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
