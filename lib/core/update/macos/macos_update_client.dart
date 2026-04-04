import 'dart:io';

import 'package:archive/archive_io.dart';

const _defaultMacosUpdateNetworkTimeout = Duration(seconds: 15);

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
    HttpClient Function()? httpClientFactory,
    Duration? networkTimeoutOverride,
  })  : _executablePath = executablePath,
        _processStarter = processStarter ?? _defaultProcessStarter,
        _environment = environment,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _networkTimeoutOverride = networkTimeoutOverride;

  final String? _executablePath;
  final MacosProcessStarter _processStarter;
  final Map<String, String>? _environment;
  final HttpClient Function() _httpClientFactory;
  final Duration? _networkTimeoutOverride;

  String get _resolvedExecutablePath =>
      _executablePath ?? Platform.resolvedExecutable;

  Map<String, String> get _resolvedEnvironment =>
      _environment ?? Platform.environment;
  Duration get _networkTimeout =>
      _networkTimeoutOverride ?? _defaultMacosUpdateNetworkTimeout;

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
    try {
      String archivePath;
      if (archiveUri.scheme == 'file') {
        archivePath = archiveUri.toFilePath();
      } else {
        final archiveFile = File(
          '${tempRoot.path}${Platform.pathSeparator}${_resolveAssetFileName(archiveUri)}',
        );
        await _materializeArchive(archiveUri, archiveFile);
        archivePath = archiveFile.path;
      }

      final extractedDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}payload',
      );
      await extractedDir.create(recursive: true);
      await extractFileToDisk(archivePath, extractedDir.path);

      final extractedApp = _resolveExtractedAppBundle(extractedDir);
      final executableName =
          File(_resolvedExecutablePath).uri.pathSegments.last;
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

      if (!Platform.isWindows) {
        final modeResult = await Process.run('chmod', ['+x', script.path]);
        if (modeResult.exitCode != 0) {
          throw StateError('macos_update_chmod_failed_${modeResult.stderr}');
        }
      }

      await _processStarter(
        '/bin/sh',
        [script.path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      try {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }

  static String? resolveManagedAppBundlePath({
    String? executablePath,
    Map<String, String>? environment,
  }) {
    final resolvedExecutablePath =
        _normalizePath((executablePath ?? Platform.resolvedExecutable).trim());
    final resolvedEnvironment = environment ?? Platform.environment;
    if (resolvedExecutablePath.isEmpty) {
      return null;
    }

    final segments = resolvedExecutablePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 4) {
      return null;
    }

    final macosIndex = segments.length - 2;
    final contentsIndex = segments.length - 3;
    final appIndex = segments.length - 4;
    if (segments[macosIndex] != 'MacOS' ||
        segments[contentsIndex] != 'Contents') {
      return null;
    }

    final appBundlePath = '/${segments.take(appIndex + 1).join('/')}';
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

  Future<void> _materializeArchive(Uri uri, File destination) async {
    if (destination.existsSync()) {
      await destination.delete();
    }
    if (uri.scheme == 'file') {
      await File(uri.toFilePath()).copy(destination.path);
      return;
    }

    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri).timeout(_networkTimeout);
      final response = await request.close().timeout(_networkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'macos_update_download_failed_http_${response.statusCode}');
      }

      final sink = destination.openWrite();
      try {
        await response.timeout(_networkTimeout).pipe(sink);
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
PS_BIN="\${PS_BIN:-/bin/ps}"
DITTO_BIN="\${DITTO_BIN:-/usr/bin/ditto}"
XATTR_BIN="\${XATTR_BIN:-/usr/bin/xattr}"
OPEN_BIN="\${OPEN_BIN:-/usr/bin/open}"
INITIAL_START_MAX_RETRIES="\${INITIAL_START_MAX_RETRIES:-3}"
INITIAL_START_RETRY_DELAY="\${INITIAL_START_RETRY_DELAY:-1}"
waited=0

process_start_time() {
  "\$PS_BIN" -o lstart= -p "\$1" 2>/dev/null | sed 's/^ *//' || true
}

capture_initial_process_start_time() {
  local attempts=0
  local start_time
  while true; do
    if ! kill -0 "\$APP_PID" 2>/dev/null; then
      return 2
    fi

    start_time=\$(process_start_time "\$APP_PID")
    if [ -n "\$start_time" ]; then
      printf '%s\n' "\$start_time"
      return 0
    fi

    attempts=\$((attempts + 1))
    if [ "\$attempts" -ge "\$INITIAL_START_MAX_RETRIES" ]; then
      return 1
    fi

    sleep "\$INITIAL_START_RETRY_DELAY"
  done
}

copy_app_bundle() {
  "\$DITTO_BIN" "\$REPLACEMENT_APP" "\$TARGET_APP"
}

APP_START=""
if kill -0 "\$APP_PID" 2>/dev/null; then
  if APP_START=\$(capture_initial_process_start_time); then
    :
  else
    capture_status=\$?
    if [ "\$capture_status" -eq 1 ]; then
      rm -rf "\$TEMP_ROOT" || true
      exit 1
    fi

    APP_START=""
  fi
  if [ -z "\$APP_START" ] && kill -0 "\$APP_PID" 2>/dev/null; then
    rm -rf "\$TEMP_ROOT" || true
    exit 1
  fi
fi

same_process_running() {
  if ! kill -0 "\$APP_PID" 2>/dev/null; then
    return 1
  fi

  if [ -z "\$APP_START" ]; then
    return 1
  fi

  local current_start
  current_start=\$(process_start_time "\$APP_PID")
  if [ -z "\$current_start" ]; then
    return 0
  fi

  [ "\$current_start" = "\$APP_START" ]
}

while same_process_running && [ "\$waited" -lt "\$MAX_WAIT" ]; do
  sleep 1
  waited=\$((waited + 1))
done

if same_process_running; then
  rm -rf "\$TEMP_ROOT" || true
  exit 1
fi

rm -rf "\$BACKUP_APP"
mv "\$TARGET_APP" "\$BACKUP_APP"

if copy_app_bundle; then
  "\$XATTR_BIN" -dr com.apple.quarantine "\$TARGET_APP" >/dev/null 2>&1 || true
  "\$OPEN_BIN" -a "\$TARGET_APP" >/dev/null 2>&1 || nohup "\$TARGET_EXECUTABLE" >/dev/null 2>&1 &
  rm -rf "\$BACKUP_APP" "\$TEMP_ROOT" || true
else
  mv "\$TARGET_APP" "\$TARGET_APP.failed" 2>/dev/null || true
  mv "\$BACKUP_APP" "\$TARGET_APP" || {
    rm -rf "\$TEMP_ROOT" || true
    exit 1
  }
  rm -rf "\$TARGET_APP.failed" || true
  "\$OPEN_BIN" -a "\$TARGET_APP" >/dev/null 2>&1 || true
  rm -rf "\$TEMP_ROOT" || true
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
