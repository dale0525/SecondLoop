import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _defaultReleaseApiOrigin = String.fromEnvironment(
  'SECONDLOOP_RELEASE_API_ORIGIN',
  defaultValue: 'https://secondloop.app',
);
const _defaultReleaseRepo = String.fromEnvironment(
  'SECONDLOOP_RELEASE_REPO',
  defaultValue: 'dale0525/SecondLoop',
);

enum AppUpdatePlatform {
  windows,
  macos,
  linux,
  android,
  ios,
  unsupported,
}

enum AppUpdateInstallMode {
  seamlessRestart,
  externalDownload,
}

class AppRuntimeVersion {
  const AppRuntimeVersion({
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final String buildNumber;

  String get display {
    final cleanBuild = buildNumber.trim();
    if (cleanBuild.isEmpty) return version;
    return '$version+$cleanBuild';
  }
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.downloadUri,
  });

  final String name;
  final Uri downloadUri;
}

class AppUpdateAvailability {
  const AppUpdateAvailability({
    required this.currentVersion,
    required this.latestTag,
    required this.releasePageUri,
    required this.installMode,
    this.asset,
  });

  final String currentVersion;
  final String latestTag;
  final Uri releasePageUri;
  final AppUpdateInstallMode installMode;
  final AppUpdateAsset? asset;

  Uri get downloadUri => asset?.downloadUri ?? releasePageUri;
  bool get canSeamlessInstall =>
      installMode == AppUpdateInstallMode.seamlessRestart;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    this.update,
    this.errorMessage,
  });

  final String currentVersion;
  final AppUpdateAvailability? update;
  final String? errorMessage;

  bool get isUpToDate => update == null && errorMessage == null;
}

typedef AppUpdateReleaseJsonFetcher = Future<Map<String, Object?>> Function(
  Uri uri,
);
typedef AppRuntimeVersionLoader = Future<AppRuntimeVersion> Function();

int compareReleaseTagWithCurrentVersion(
    String releaseTag, String currentVersion) {
  final releaseSegments = _parseVersionSegments(releaseTag);
  final currentSegments = _parseVersionSegments(currentVersion);
  if (releaseSegments.isEmpty || currentSegments.isEmpty) return 0;

  final comparedLength = max(
    min(3, releaseSegments.length),
    min(3, currentSegments.length),
  );

  for (var i = 0; i < comparedLength; i++) {
    final releaseValue = i < releaseSegments.length ? releaseSegments[i] : 0;
    final currentValue = i < currentSegments.length ? currentSegments[i] : 0;
    if (releaseValue != currentValue) {
      return releaseValue.compareTo(currentValue);
    }
  }

  return 0;
}

class AppUpdateService {
  AppUpdateService({
    HttpClient? httpClient,
    AppUpdateReleaseJsonFetcher? releaseJsonFetcher,
    AppRuntimeVersionLoader? currentVersionLoader,
    AppUpdatePlatform? platformOverride,
    bool? releaseModeOverride,
  })  : _httpClient = httpClient ?? HttpClient(),
        _releaseJsonFetcher = releaseJsonFetcher,
        _currentVersionLoader = currentVersionLoader,
        _platformOverride = platformOverride,
        _releaseModeOverride = releaseModeOverride;

  final HttpClient _httpClient;
  final AppUpdateReleaseJsonFetcher? _releaseJsonFetcher;
  final AppRuntimeVersionLoader? _currentVersionLoader;
  final AppUpdatePlatform? _platformOverride;
  final bool? _releaseModeOverride;

  AppUpdatePlatform get _platform => _platformOverride ?? _detectPlatform();

  bool get _isReleaseMode => _releaseModeOverride ?? kReleaseMode;

  Future<AppUpdateCheckResult> checkForUpdates() async {
    final runtimeVersion = await _loadCurrentVersion();
    final currentVersion = runtimeVersion.version.trim().isEmpty
        ? '0.0.0'
        : runtimeVersion.version.trim();

    if (_platform == AppUpdatePlatform.unsupported) {
      return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
    }

    Map<String, Object?>? release;
    Object? lastError;
    for (final endpoint in _buildReleaseEndpoints()) {
      try {
        release = await _fetchReleaseJson(endpoint);
        break;
      } catch (error) {
        lastError = error;
      }
    }

    if (release == null) {
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        errorMessage: lastError?.toString() ?? 'failed_to_fetch_release',
      );
    }

    final latestTag = _readString(release, 'tag_name');
    if (latestTag == null || latestTag.trim().isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        errorMessage: 'invalid_release_tag',
      );
    }

    final releasePageUri = _parseUri(_readString(release, 'html_url')) ??
        _buildFallbackReleasePageUri();

    if (compareReleaseTagWithCurrentVersion(latestTag, currentVersion) <= 0) {
      return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
    }

    final assets = _parseAssets(release['assets']);
    final matchedAsset = _matchAssetForCurrentPlatform(assets);
    final installMode = _resolveInstallMode(matchedAsset);

    return AppUpdateCheckResult(
      currentVersion: runtimeVersion.display,
      update: AppUpdateAvailability(
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        releasePageUri: releasePageUri,
        installMode: installMode,
        asset: matchedAsset,
      ),
    );
  }

  Future<void> installAndRestart(AppUpdateAvailability update) async {
    if (update.installMode != AppUpdateInstallMode.seamlessRestart) {
      throw StateError('seamless_update_not_supported');
    }

    final asset = update.asset;
    if (asset == null) {
      throw StateError('missing_update_asset');
    }

    final platform = _platform;
    if (platform != AppUpdatePlatform.linux) {
      throw StateError('seamless_update_not_supported_for_$platform');
    }

    final tempRoot =
        await Directory.systemTemp.createTemp('secondloop_update_');
    final archiveFile = File('${tempRoot.path}/payload_${asset.name}');
    final extractedDir = Directory('${tempRoot.path}/payload');
    await extractedDir.create(recursive: true);

    await _downloadToFile(asset.downloadUri, archiveFile);
    await extractFileToDisk(archiveFile.path, extractedDir.path);

    final sourceDir = _resolveExtractedSourceDir(extractedDir, platform);
    final executablePath = File(Platform.resolvedExecutable).absolute.path;
    final appDirPath = File(executablePath).parent.path;

    final script = File('${tempRoot.path}/apply_update.sh');
    await script.writeAsString(
      _buildLinuxUpdaterScript(
        pid: pid,
        appDirPath: appDirPath,
        executablePath: executablePath,
        sourceDirPath: sourceDir.path,
        tempRootPath: tempRoot.path,
      ),
    );
    await script.setLastModified(DateTime.now());
    final modeResult = await Process.run('chmod', ['+x', script.path]);
    if (modeResult.exitCode != 0) {
      throw StateError('chmod_failed_${modeResult.stderr}');
    }

    await Process.start(
      '/bin/sh',
      [script.path],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  void dispose() {
    _httpClient.close(force: true);
  }

  Future<AppRuntimeVersion> _loadCurrentVersion() async {
    final loader = _currentVersionLoader;
    if (loader != null) {
      return loader();
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return AppRuntimeVersion(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
      );
    } catch (_) {
      return const AppRuntimeVersion(version: '0.0.0', buildNumber: '0');
    }
  }

  Future<Map<String, Object?>> _fetchReleaseJson(Uri uri) async {
    final fetcher = _releaseJsonFetcher;
    if (fetcher != null) {
      return fetcher(uri);
    }

    final req = await _httpClient.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close();

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'http_${resp.statusCode}',
        uri: uri,
      );
    }

    final body = await utf8.decoder.bind(resp).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_release_payload');
    }

    final mapped = <String, Object?>{};
    for (final entry in decoded.entries) {
      mapped[entry.key] = entry.value;
    }
    return mapped;
  }

  Future<void> _downloadToFile(Uri uri, File output) async {
    final req = await _httpClient.getUrl(uri);
    final resp = await req.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('download_failed_${resp.statusCode}', uri: uri);
    }

    final sink = output.openWrite();
    try {
      await resp.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  List<Uri> _buildReleaseEndpoints() {
    final configuredOrigin = _defaultReleaseApiOrigin.trim();
    final repo = _defaultReleaseRepo.trim();

    final endpoints = <Uri>[];
    final apiOrigin = _parseUri(configuredOrigin);
    if (apiOrigin != null) {
      endpoints.add(apiOrigin.resolve('/api/releases/latest'));
    }

    if (repo.isNotEmpty) {
      endpoints
          .add(Uri.https('api.github.com', '/repos/$repo/releases/latest'));
    }

    return endpoints;
  }

  Uri _buildFallbackReleasePageUri() {
    final repo = _defaultReleaseRepo.trim();
    if (repo.isEmpty) {
      final origin = _parseUri(_defaultReleaseApiOrigin.trim());
      if (origin != null) return origin;
      return Uri.parse('https://github.com');
    }
    return Uri.parse('https://github.com/$repo/releases/latest');
  }

  List<AppUpdateAsset> _parseAssets(Object? rawAssets) {
    if (rawAssets is! List) return const [];

    final parsed = <AppUpdateAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final name = item['name'];
      final url = item['browser_download_url'];
      if (name is! String || url is! String) continue;
      final uri = _parseUri(url);
      if (uri == null) continue;
      parsed.add(AppUpdateAsset(name: name, downloadUri: uri));
    }

    return parsed;
  }

  AppUpdateAsset? _matchAssetForCurrentPlatform(List<AppUpdateAsset> assets) {
    RegExp? matcher;
    switch (_platform) {
      case AppUpdatePlatform.windows:
        matcher = RegExp(r'^SecondLoop-windows-x64-.*\.msi$');
      case AppUpdatePlatform.macos:
        matcher = RegExp(r'^SecondLoop-macos-.*\.(dmg|zip)$');
      case AppUpdatePlatform.linux:
        matcher = RegExp(r'^SecondLoop-linux-x64-.*\.tar\.gz$');
      case AppUpdatePlatform.android:
        matcher = RegExp(r'^SecondLoop-android-.*\.apk$');
      case AppUpdatePlatform.ios:
      case AppUpdatePlatform.unsupported:
        matcher = null;
    }

    if (matcher == null) return null;

    for (final asset in assets) {
      if (matcher.hasMatch(asset.name)) return asset;
    }
    return null;
  }

  AppUpdateInstallMode _resolveInstallMode(AppUpdateAsset? asset) {
    if (!_isReleaseMode || asset == null) {
      return AppUpdateInstallMode.externalDownload;
    }

    return switch (_platform) {
      AppUpdatePlatform.linux when asset.name.endsWith('.tar.gz') =>
        AppUpdateInstallMode.seamlessRestart,
      _ => AppUpdateInstallMode.externalDownload,
    };
  }

  Directory _resolveExtractedSourceDir(
    Directory extractedDir,
    AppUpdatePlatform platform,
  ) {
    if (platform == AppUpdatePlatform.linux) {
      final bundle = Directory('${extractedDir.path}/bundle');
      if (bundle.existsSync()) return bundle;
    }

    final entries = extractedDir
        .listSync()
        .where((entry) =>
            entry.path.split(Platform.pathSeparator).last != '.DS_Store')
        .toList(growable: false);

    if (entries.length == 1 && entries.first is Directory) {
      return entries.first as Directory;
    }

    return extractedDir;
  }

  String _buildLinuxUpdaterScript({
    required int pid,
    required String appDirPath,
    required String executablePath,
    required String sourceDirPath,
    required String tempRootPath,
  }) {
    final safePid = pid.toString();
    final appDir = _shellQuote(appDirPath);
    final executable = _shellQuote(executablePath);
    final sourceDir = _shellQuote(sourceDirPath);
    final tempRoot = _shellQuote(tempRootPath);

    return '''#!/usr/bin/env bash
set -euo pipefail
APP_PID=$safePid
APP_DIR=$appDir
EXE_PATH=$executable
SOURCE_DIR=$sourceDir
TEMP_ROOT=$tempRoot

while kill -0 "\$APP_PID" 2>/dev/null; do
  sleep 1
done

cp -a "\$SOURCE_DIR"/. "\$APP_DIR"/
chmod +x "\$EXE_PATH" || true
nohup "\$EXE_PATH" >/dev/null 2>&1 &
rm -rf "\$TEMP_ROOT"
''';
  }

  static String? _readString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static Uri? _parseUri(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) return null;
    return uri;
  }
}

List<int> _parseVersionSegments(String input) {
  final cleaned = input.trim();
  if (cleaned.isEmpty) return const [];
  final matches = RegExp(r'\d+').allMatches(cleaned);
  if (matches.isEmpty) return const [];

  final segments = <int>[];
  for (final match in matches) {
    final parsed = int.tryParse(match.group(0) ?? '');
    if (parsed == null) continue;
    segments.add(parsed);
    if (segments.length >= 4) break;
  }
  return segments;
}

AppUpdatePlatform _detectPlatform() {
  if (kIsWeb) return AppUpdatePlatform.unsupported;
  if (Platform.isWindows) return AppUpdatePlatform.windows;
  if (Platform.isMacOS) return AppUpdatePlatform.macos;
  if (Platform.isLinux) return AppUpdatePlatform.linux;
  if (Platform.isAndroid) return AppUpdatePlatform.android;
  if (Platform.isIOS) return AppUpdatePlatform.ios;
  return AppUpdatePlatform.unsupported;
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}
