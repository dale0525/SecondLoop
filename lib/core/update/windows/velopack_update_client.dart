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
    if (!isAvailable()) {
      throw StateError('windows_velopack_unavailable');
    }

    final result = await _processRunner(_updateExePath, [
      'apply',
      '--silent',
    ]);

    if (result.exitCode != 0) {
      throw StateError('windows_velopack_apply_failed_${result.stderr}');
    }
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }
}
