import 'dart:io';

import 'velopack_paths.dart';

typedef VelopackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

abstract class WindowsStagedUpdateClient {
  bool isAvailable();

  Future<void> stageAsset(Uri assetDownloadUri);

  Future<void> applyPendingOnStartup();
}

class VelopackUpdateClient implements WindowsStagedUpdateClient {
  VelopackUpdateClient({
    String? updateExecutablePath,
    VelopackProcessRunner? processRunner,
  })  : _updateExecutablePath = updateExecutablePath,
        _processRunner = processRunner ?? _defaultProcessRunner;

  final String? _updateExecutablePath;
  final VelopackProcessRunner _processRunner;

  String get _updateExePath =>
      _updateExecutablePath ?? resolveVelopackUpdateExePath();

  @override
  bool isAvailable() {
    return File(_updateExePath).existsSync();
  }

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {
    if (!isAvailable()) {
      throw StateError('windows_velopack_unavailable');
    }

    final result = await _processRunner(_updateExePath, [
      'stage',
      '--package',
      assetDownloadUri.toString(),
    ]);

    if (result.exitCode != 0) {
      throw StateError('windows_velopack_stage_failed_${result.stderr}');
    }
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
      throw StateError('windows_velopack_apply_failed_${result.stderr}');
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
}
