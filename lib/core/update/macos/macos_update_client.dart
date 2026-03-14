import 'dart:io';

import 'package:archive/archive_io.dart';

typedef MacosProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

abstract class MacosManagedUpdateClient {
  bool isSupportedInstallLocation();

  Future<void> installArchiveAndRestart(
    Uri archiveUri, {
    required int waitPid,
  });
}

class DefaultMacosManagedUpdateClient implements MacosManagedUpdateClient {
  DefaultMacosManagedUpdateClient({
    String? executablePath,
    MacosProcessStarter? processStarter,
    Map<String, String>? environment,
  })  : _executablePath = executablePath,
        _processStarter = processStarter ?? _defaultProcessStarter,
        _environment = environment;

  final String? _executablePath;
  final MacosProcessStarter _processStarter;
  final Map<String, String>? _environment;

  String get _resolvedExecutablePath =>
      _executablePath ?? Platform.resolvedExecutable;

  Map<String, String> get _resolvedEnvironment =>
      _environment ?? Platform.environment;

  @override
  bool isSupportedInstallLocation() {
    return resolveManagedAppBundlePath(
          executablePath: _resolvedExecutablePath,
          environment: _resolvedEnvironment,
        ) !=
        null;
  }

  @override
  Future<void> installArchiveAndRestart(
    Uri archiveUri, {
    required int waitPid,
  }) async {
    final appBundlePath = resolveManagedAppBundlePath(
      executablePath: _resolvedExecutablePath,
      environment: _resolvedEnvironment,
    );
    if (appBundlePath == null) {
      throw StateError('macos_update_unsupported_install_location');
    }

    final tempRoot = await Directory.systemTemp.createTemp(
      'secondloop_macos_update_',
    );
    final archiveFile = File(
      '${tempRoot.path}${Platform.pathSeparator}${_resolveAssetFileName(archiveUri)}',
    );
    await _materializeArchive(archiveUri, archiveFile);

    final extractedDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}payload',
    );
    await extractedDir.create(recursive: true);
    await extractFileToDisk(archiveFile.path, extractedDir.path);

    final extractedApp = _resolveExtractedAppBundle(extractedDir);
    final executableName = File(_resolvedExecutablePath).uri.pathSegments.last;
    final script = File(
      '${tempRoot.path}${Platform.pathSeparator}apply_update.sh',
    );
    await script.writeAsString(
      _buildMacosUpdaterScript(
        pid: waitPid,
        appBundlePath: appBundlePath,
        replacementAppPath: extractedApp.path,
        executableName: executableName,
        tempRootPath: tempRoot.path,
      ),
    );

    final modeResult = await Process.run('chmod', ['+x', script.path]);
    if (modeResult.exitCode != 0) {
      throw StateError('macos_update_chmod_failed_${modeResult.stderr}');
    }

    await _processStarter(
      '/bin/sh',
      [script.path],
      mode: ProcessStartMode.detached,
    );
  }

  static String? resolveManagedAppBundlePath({
    String? executablePath,
    Map<String, String>? environment,
  }) {
    final resolvedExecutablePath =
        executablePath ?? Platform.resolvedExecutable;
    final resolvedEnvironment = environment ?? Platform.environment;
    final executableFile = File(resolvedExecutablePath).absolute;
    final macosDir = executableFile.parent;
    if (macosDir.path.split(Platform.pathSeparator).last != 'MacOS') {
      return null;
    }

    final contentsDir = macosDir.parent;
    if (contentsDir.path.split(Platform.pathSeparator).last != 'Contents') {
      return null;
    }

    final appBundleDir = contentsDir.parent;
    final appBundlePath = appBundleDir.absolute.path;
    if (!appBundlePath.endsWith('.app')) {
      return null;
    }

    final normalizedActual = _normalizePath(appBundlePath);
    final supported = <String>{'/Applications/SecondLoop.app'};
    final home = resolvedEnvironment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      supported.add(_normalizePath('$home/Applications/SecondLoop.app'));
    }

    return supported.contains(normalizedActual) ? appBundlePath : null;
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(executable, arguments, mode: mode);
  }

  static String _resolveAssetFileName(Uri archiveUri) {
    final rawName = archiveUri.pathSegments.isEmpty
        ? ''
        : archiveUri.pathSegments.last.trim();
    final normalized = Uri.decodeComponent(rawName);
    if (normalized.isNotEmpty) return normalized;
    return 'SecondLoop-macos-update.app.tar.gz';
  }

  static Future<void> _materializeArchive(Uri uri, File destination) async {
    if (destination.existsSync()) {
      await destination.delete();
    }
    if (uri.scheme == 'file') {
      await File(uri.toFilePath()).copy(destination.path);
      return;
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'macos_update_download_failed_http_${response.statusCode}');
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

  static Directory _resolveExtractedAppBundle(Directory extractedDir) {
    final directApp = Directory(
      '${extractedDir.path}${Platform.pathSeparator}SecondLoop.app',
    );
    if (directApp.existsSync()) {
      return directApp;
    }

    for (final entity in extractedDir.listSync(recursive: true)) {
      if (entity is! Directory) continue;
      if (entity.path.endsWith('${Platform.pathSeparator}SecondLoop.app') ||
          entity.path.endsWith('SecondLoop.app')) {
        return entity;
      }
    }

    throw StateError('macos_update_missing_app_bundle');
  }

  static String _buildMacosUpdaterScript({
    required int pid,
    required String appBundlePath,
    required String replacementAppPath,
    required String executableName,
    required String tempRootPath,
  }) {
    final safePid = pid.toString();
    final targetApp = _shellQuote(appBundlePath);
    final replacementApp = _shellQuote(replacementAppPath);
    final backupApp = _shellQuote('$appBundlePath.backup');
    final tempRoot = _shellQuote(tempRootPath);
    final targetExecutable = _shellQuote(
      '$appBundlePath/Contents/MacOS/$executableName',
    );

    return '''#!/usr/bin/env bash
set -euo pipefail
APP_PID=$safePid
TARGET_APP=$targetApp
REPLACEMENT_APP=$replacementApp
BACKUP_APP=$backupApp
TEMP_ROOT=$tempRoot
TARGET_EXECUTABLE=$targetExecutable
MAX_WAIT=60
waited=0
APP_START=\$(/bin/ps -o lstart= -p "\$APP_PID" 2>/dev/null | sed 's/^ *//')

while kill -0 "\$APP_PID" 2>/dev/null && [ "\$waited" -lt "\$MAX_WAIT" ]; do
  CURRENT_START=\$(/bin/ps -o lstart= -p "\$APP_PID" 2>/dev/null | sed 's/^ *//')
  if [ -n "\$APP_START" ] && [ "\$CURRENT_START" != "\$APP_START" ]; then
    break
  fi
  sleep 1
  waited=\$((waited + 1))
done

rm -rf "\$BACKUP_APP"
mv "\$TARGET_APP" "\$BACKUP_APP"

if ditto "\$REPLACEMENT_APP" "\$TARGET_APP"; then
  /usr/bin/xattr -dr com.apple.quarantine "\$TARGET_APP" >/dev/null 2>&1 || true
  open -a "\$TARGET_APP" >/dev/null 2>&1 || nohup "\$TARGET_EXECUTABLE" >/dev/null 2>&1 &
  rm -rf "\$BACKUP_APP" "\$TEMP_ROOT"
else
  mv "\$TARGET_APP" "\$TARGET_APP.failed" 2>/dev/null || true
  mv "\$BACKUP_APP" "\$TARGET_APP" || {
    exit 1
  }
  rm -rf "\$TARGET_APP.failed" || true
  open -a "\$TARGET_APP" >/dev/null 2>&1 || true
  exit 1
fi
''';
  }

  static String _normalizePath(String value) {
    return value.replaceAll('\\', '/');
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
