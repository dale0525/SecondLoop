import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'macos/macos_update_client.dart';
import 'update_event_log.dart';
import 'windows/velopack_update_client.dart';

part 'app_update_service_android_support.dart';
part 'app_update_service_asset_matching.dart';
part 'app_update_service_utils.dart';

const _defaultReleaseApiOrigin = String.fromEnvironment(
  'SECONDLOOP_RELEASE_API_ORIGIN',
  defaultValue: '',
);
const _defaultReleaseRepo = String.fromEnvironment(
  'SECONDLOOP_RELEASE_REPO',
  defaultValue: 'dale0525/SecondLoop',
);
const _defaultUpdatePublicKey = String.fromEnvironment(
  'SECONDLOOP_UPDATE_PUBLIC_KEY',
  defaultValue: '',
);
const _defaultUpdateNetworkTimeout = Duration(seconds: 15);

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
  stagedNextLaunch,
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
    this.sha256,
    this.installMode,
  });

  final String name;
  final Uri downloadUri;
  final String? sha256;
  final String? installMode;
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
  bool get canStageForNextLaunch =>
      installMode == AppUpdateInstallMode.stagedNextLaunch;

  bool get canUseAndroidApkInstaller =>
      asset != null &&
      asset!.sha256?.trim().isNotEmpty == true &&
      isAndroidApkAssetForUpdate(asset!);
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
typedef AndroidSupportedAbisLoader = Future<List<String>> Function();

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
    String? releaseApiOriginOverride,
    String? releaseRepoOverride,
    WindowsStagedUpdateClient? windowsStagedUpdateClient,
    MacosManagedUpdateClient? macosManagedUpdateClient,
    String? updatePublicKeyOverride,
    UpdateEventLogger? updateEventLogger,
    void Function(int code)? processExit,
    Duration? networkTimeoutOverride,
    AndroidSupportedAbisLoader? androidSupportedAbisLoader,
    List<String>? androidSupportedAbisOverride,
  })  : _httpClient = httpClient ?? HttpClient(),
        _releaseJsonFetcher = releaseJsonFetcher,
        _currentVersionLoader = currentVersionLoader,
        _platformOverride = platformOverride,
        _releaseModeOverride = releaseModeOverride,
        _releaseApiOriginOverride = releaseApiOriginOverride,
        _releaseRepoOverride = releaseRepoOverride,
        _windowsStagedUpdateClient = windowsStagedUpdateClient,
        _macosManagedUpdateClient = macosManagedUpdateClient,
        _updatePublicKeyOverride = updatePublicKeyOverride,
        _updateEventLogger =
            updateEventLogger ?? SharedPrefsUpdateEventLogger(),
        _processExit = processExit,
        _networkTimeoutOverride = networkTimeoutOverride,
        _androidSupportedAbisLoader = androidSupportedAbisLoader,
        _androidSupportedAbisOverride = androidSupportedAbisOverride;

  final HttpClient _httpClient;
  final AppUpdateReleaseJsonFetcher? _releaseJsonFetcher;
  final AppRuntimeVersionLoader? _currentVersionLoader;
  final AppUpdatePlatform? _platformOverride;
  final bool? _releaseModeOverride;
  final String? _releaseApiOriginOverride;
  final String? _releaseRepoOverride;
  final WindowsStagedUpdateClient? _windowsStagedUpdateClient;
  final MacosManagedUpdateClient? _macosManagedUpdateClient;
  final String? _updatePublicKeyOverride;
  final UpdateEventLogger _updateEventLogger;
  final void Function(int code)? _processExit;
  final Duration? _networkTimeoutOverride;
  final AndroidSupportedAbisLoader? _androidSupportedAbisLoader;
  final List<String>? _androidSupportedAbisOverride;

  AppUpdatePlatform get _platform => _platformOverride ?? _detectPlatform();

  bool get _isReleaseMode => _releaseModeOverride ?? kReleaseMode;
  String get _releaseApiOrigin =>
      _releaseApiOriginOverride ?? _defaultReleaseApiOrigin;
  String get _releaseRepo => _releaseRepoOverride ?? _defaultReleaseRepo;
  String get releaseRepo => _releaseRepo;
  String get _updatePublicKey =>
      _updatePublicKeyOverride ?? _defaultUpdatePublicKey;
  Duration get _networkTimeout =>
      _networkTimeoutOverride ?? _defaultUpdateNetworkTimeout;
  void _exitProcess(int code) => (_processExit ?? exit)(code);

  late final WindowsStagedUpdateClient? _resolvedWindowsStagedUpdateClient =
      () {
    if (_windowsStagedUpdateClient != null) {
      return _windowsStagedUpdateClient;
    }
    if (_platform != AppUpdatePlatform.windows) {
      return null;
    }
    return VelopackUpdateClient();
  }();

  late final MacosManagedUpdateClient? _resolvedMacosManagedUpdateClient = () {
    if (_macosManagedUpdateClient != null) {
      return _macosManagedUpdateClient;
    }
    if (_platform != AppUpdatePlatform.macos) {
      return null;
    }
    return DefaultMacosManagedUpdateClient();
  }();

  Future<AppUpdateCheckResult> checkForUpdates() async {
    final runtimeVersion = await _loadCurrentVersion();
    final currentVersion = runtimeVersion.version.trim().isEmpty
        ? '0.0.0'
        : runtimeVersion.version.trim();

    await _recordEvent(
      UpdateEventType.checkStarted,
      currentVersion: runtimeVersion.display,
    );

    if (_platform == AppUpdatePlatform.unsupported) {
      await _recordEvent(
        UpdateEventType.checkSucceeded,
        currentVersion: runtimeVersion.display,
        message: 'unsupported_platform',
      );
      return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
    }

    Map<String, Object?>? release;
    String? releaseTag;
    Object? lastError;
    var sawUpToDateOrOlderRelease = false;
    final windowsStagedClient = _resolvedWindowsStagedUpdateClient;
    final windowsManagedRuntimeAvailable =
        windowsStagedClient != null && windowsStagedClient.isAvailable();
    final androidSupportedAbis = _platform == AppUpdatePlatform.android
        ? await _loadAndroidSupportedAbisImpl(
            override: _androidSupportedAbisOverride,
            loader: _androidSupportedAbisLoader,
          )
        : const <String>[];
    final releaseEndpoints = _buildReleaseEndpoints();
    for (final endpoint in releaseEndpoints) {
      try {
        final candidate = await _fetchReleaseJson(endpoint);
        final candidateTag = _normalizeLatestTag(
          _readString(candidate, 'tag_name') ??
              _readString(candidate, 'version'),
        );
        if (candidateTag == null || candidateTag.trim().isEmpty) {
          lastError = 'invalid_release_tag';
          continue;
        }
        if (compareReleaseTagWithCurrentVersion(candidateTag, currentVersion) <=
            0) {
          sawUpToDateOrOlderRelease = true;
          continue;
        }
        if (!_releaseHasUsableAssetForCurrentPlatform(
          candidate,
          windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
          androidSupportedAbis: androidSupportedAbis,
        )) {
          lastError = StateError('no_platform_asset_for_${_platform.name}');
          continue;
        }
        if (releaseTag == null ||
            compareReleaseTagWithCurrentVersion(candidateTag, releaseTag) > 0) {
          release = candidate;
          releaseTag = candidateTag;
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (release == null) {
      if (sawUpToDateOrOlderRelease) {
        await _recordEvent(
          UpdateEventType.checkSucceeded,
          currentVersion: runtimeVersion.display,
          message: 'up_to_date',
        );
        return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
      }
      await _recordFailure(
        UpdateEventType.checkFailed,
        lastError ?? 'failed_to_fetch_release',
        currentVersion: runtimeVersion.display,
      );
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        errorMessage: lastError?.toString() ?? 'failed_to_fetch_release',
      );
    }

    final latestTag = _normalizeLatestTag(
      _readString(release, 'tag_name') ?? _readString(release, 'version'),
    );
    if (latestTag == null || latestTag.trim().isEmpty) {
      await _recordFailure(
        UpdateEventType.checkFailed,
        'invalid_release_tag',
        currentVersion: runtimeVersion.display,
      );
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        errorMessage: 'invalid_release_tag',
      );
    }

    final releasePageUri =
        _parseUri(_readString(release, 'release_page_url')) ??
            _parseUri(_readString(release, 'html_url')) ??
            _buildFallbackReleasePageUriImpl(_releaseRepo, _releaseApiOrigin);

    if (compareReleaseTagWithCurrentVersion(latestTag, currentVersion) <= 0) {
      await _recordEvent(
        UpdateEventType.checkSucceeded,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        message: 'up_to_date',
      );
      return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
    }

    final macosManagedClient = _resolvedMacosManagedUpdateClient;
    final macosManagedInstallSupported = macosManagedClient != null &&
        macosManagedClient.isSupportedInstallLocation();
    final manifestAsset = _matchManifestAssetForCurrentPlatformImpl(
      _platform,
      release,
      androidSupportedAbis: androidSupportedAbis,
    );
    final assets = _parseAssetsImpl(release['assets']);
    final matchedAsset = manifestAsset ??
        _matchAssetForCurrentPlatformImpl(
          _platform,
          assets,
          windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
          androidSupportedAbis: androidSupportedAbis,
        );
    if (_platform == AppUpdatePlatform.android &&
        matchedAsset == null &&
        _shouldOfferAndroidManualFallback(
          release,
          androidSupportedAbis: androidSupportedAbis,
        )) {
      await _recordEvent(
        UpdateEventType.updateAvailable,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        installMode: AppUpdateInstallMode.externalDownload,
        message: 'android_manual_fallback',
      );
      await _recordEvent(
        UpdateEventType.checkSucceeded,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        installMode: AppUpdateInstallMode.externalDownload,
        message: 'update_available',
      );
      await _recordEvent(
        UpdateEventType.manualFallback,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        installMode: AppUpdateInstallMode.externalDownload,
        message: 'android_supported_abis_unknown',
      );
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        update: AppUpdateAvailability(
          currentVersion: runtimeVersion.display,
          latestTag: latestTag,
          releasePageUri: releasePageUri,
          installMode: AppUpdateInstallMode.externalDownload,
        ),
      );
    }
    final installMode = _resolveInstallModeImpl(
      _platform,
      _isReleaseMode,
      matchedAsset,
      windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
      macosManagedInstallSupported: macosManagedInstallSupported,
    );

    await _recordEvent(
      UpdateEventType.updateAvailable,
      currentVersion: runtimeVersion.display,
      latestTag: latestTag,
      installMode: installMode,
      message: matchedAsset?.name,
    );
    await _recordEvent(
      UpdateEventType.checkSucceeded,
      currentVersion: runtimeVersion.display,
      latestTag: latestTag,
      installMode: installMode,
      message: 'update_available',
    );
    if (installMode == AppUpdateInstallMode.externalDownload &&
        !_isAndroidApkInstallerCandidate(matchedAsset)) {
      await _recordEvent(
        UpdateEventType.manualFallback,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        installMode: installMode,
        message: _describeManualFallbackReason(matchedAsset),
      );
    }

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
    await _recordEvent(
      UpdateEventType.installStarted,
      currentVersion: update.currentVersion,
      latestTag: update.latestTag,
      installMode: update.installMode,
      message: update.asset?.name,
    );
    try {
      if (update.installMode != AppUpdateInstallMode.seamlessRestart) {
        throw StateError('seamless_update_not_supported');
      }

      final asset = update.asset;
      if (asset == null) {
        throw StateError('missing_update_asset');
      }

      final platform = _platform;
      if (platform == AppUpdatePlatform.windows) {
        final stagedClient = _resolvedWindowsStagedUpdateClient;
        if (stagedClient == null || !stagedClient.isAvailable()) {
          throw StateError('windows_velopack_unavailable');
        }
        if (stagedClient.hasPendingUpdate()) {
          await stagedClient.applyPendingAndRestart(waitPid: pid);
        } else {
          await _withPreparedAsset(asset, (localUri) async {
            await stagedClient.installAssetAndRestart(localUri, waitPid: pid);
          });
        }
        await _recordEvent(
          UpdateEventType.installDispatched,
          currentVersion: update.currentVersion,
          latestTag: update.latestTag,
          installMode: update.installMode,
          message: asset.name,
        );
        _exitProcess(0);
        return;
      }

      if (platform == AppUpdatePlatform.macos) {
        final macosClient = _resolvedMacosManagedUpdateClient;
        if (macosClient == null || !macosClient.isSupportedInstallLocation()) {
          throw StateError('macos_update_unsupported_install_location');
        }
        await _withPreparedAsset(asset, (localUri) async {
          await macosClient.installArchiveAndRestart(localUri, waitPid: pid);
        });
        await _recordEvent(
          UpdateEventType.installDispatched,
          currentVersion: update.currentVersion,
          latestTag: update.latestTag,
          installMode: update.installMode,
          message: asset.name,
        );
        _exitProcess(0);
        return;
      }

      if (platform != AppUpdatePlatform.linux) {
        throw StateError('seamless_update_not_supported_for_$platform');
      }

      final tempRoot =
          await Directory.systemTemp.createTemp('secondloop_update_');
      try {
        final archiveFile = File('${tempRoot.path}/payload_${asset.name}');
        final extractedDir = Directory('${tempRoot.path}/payload');
        await extractedDir.create(recursive: true);

        await _downloadToFile(asset.downloadUri, archiveFile);
        if (asset.sha256 != null) {
          await _verifyFileSha256(archiveFile, asset.sha256!);
        }
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
        await _recordEvent(
          UpdateEventType.installDispatched,
          currentVersion: update.currentVersion,
          latestTag: update.latestTag,
          installMode: update.installMode,
          message: asset.name,
        );
        _exitProcess(0);
      } catch (_) {
        try {
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        } catch (_) {}
        rethrow;
      }
    } catch (error) {
      await _recordFailure(
        UpdateEventType.installFailed,
        error,
        currentVersion: update.currentVersion,
        latestTag: update.latestTag,
        installMode: update.installMode,
      );
      rethrow;
    }
  }

  Future<void> stageUpdateForNextLaunch(AppUpdateAvailability update) async {
    await _recordEvent(
      UpdateEventType.stageStarted,
      currentVersion: update.currentVersion,
      latestTag: update.latestTag,
      installMode: update.installMode,
      message: update.asset?.name,
    );
    try {
      final asset = update.asset;
      if (_platform == AppUpdatePlatform.windows) {
        final stagedClient = _resolvedWindowsStagedUpdateClient;
        if (asset == null ||
            stagedClient == null ||
            !stagedClient.isAvailable()) {
          throw StateError('staged_update_not_supported_for_${_platform.name}');
        }
        await _withPreparedAsset(asset, (localUri) async {
          await stagedClient.stageAsset(localUri);
        });
        await _recordEvent(
          UpdateEventType.stageSucceeded,
          currentVersion: update.currentVersion,
          latestTag: update.latestTag,
          installMode: update.installMode,
          message: asset.name,
        );
        return;
      }
      throw StateError('staged_update_not_supported_for_${_platform.name}');
    } catch (error) {
      await _recordFailure(
        UpdateEventType.stageFailed,
        error,
        currentVersion: update.currentVersion,
        latestTag: update.latestTag,
        installMode: update.installMode,
      );
      rethrow;
    }
  }

  Future<bool> applyPendingUpdateOnStartup() async {
    if (_platform != AppUpdatePlatform.windows) {
      return false;
    }
    final stagedClient = _resolvedWindowsStagedUpdateClient;
    if (stagedClient == null || !stagedClient.isAvailable()) {
      return false;
    }
    await _recordEvent(UpdateEventType.pendingApplyStarted);
    try {
      final applied = await stagedClient.applyPendingOnStartup();
      await _recordEvent(UpdateEventType.pendingApplySucceeded);
      return applied;
    } catch (error) {
      await _recordFailure(UpdateEventType.pendingApplyFailed, error);
      rethrow;
    }
  }

  Future<void> applyStagedUpdateAndRestart() async {
    await _recordEvent(UpdateEventType.stagedRestartStarted);
    try {
      if (_platform == AppUpdatePlatform.windows) {
        final stagedClient = _resolvedWindowsStagedUpdateClient;
        if (stagedClient == null || !stagedClient.isAvailable()) {
          throw StateError(
              'staged_update_restart_not_supported_for_${_platform.name}');
        }
        await stagedClient.applyPendingAndRestart(waitPid: pid);
        await _recordEvent(UpdateEventType.stagedRestartDispatched);
        _exitProcess(0);
        return;
      }
      throw StateError(
          'staged_update_restart_not_supported_for_${_platform.name}');
    } catch (error) {
      await _recordFailure(UpdateEventType.stagedRestartFailed, error);
      rethrow;
    }
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

    final req = await _getUrlWithTimeout(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await _closeRequestWithTimeout(req);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'http_${resp.statusCode}',
        uri: uri,
      );
    }

    final bodyBytes = await _readResponseBytesWithTimeout(resp);
    if (_shouldVerifyManifestSignature(uri)) {
      await _verifySignedManifest(uri, bodyBytes);
    }

    final decoded = jsonDecode(utf8.decode(bodyBytes));
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
    final req = await _getUrlWithTimeout(uri);
    final resp = await _closeRequestWithTimeout(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('download_failed_${resp.statusCode}', uri: uri);
    }

    final sink = output.openWrite();
    try {
      await resp.timeout(_networkTimeout).pipe(sink);
    } finally {
      await sink.close();
    }
  }

  Future<HttpClientRequest> _getUrlWithTimeout(Uri uri) {
    return _httpClient.getUrl(uri).timeout(_networkTimeout);
  }

  Future<HttpClientResponse> _closeRequestWithTimeout(
    HttpClientRequest request,
  ) {
    return request.close().timeout(_networkTimeout);
  }

  Future<List<int>> _readResponseBytesWithTimeout(
    HttpClientResponse response,
  ) {
    return response.timeout(_networkTimeout).fold<List<int>>(<int>[], (
      buffer,
      data,
    ) {
      buffer.addAll(data);
      return buffer;
    });
  }

  Future<String> _readResponseTextWithTimeout(HttpClientResponse response) {
    return utf8.decoder.bind(response.timeout(_networkTimeout)).join();
  }

  List<Uri> _buildReleaseEndpoints() {
    final configuredOrigin = _releaseApiOrigin.trim();
    final repo = _releaseRepo.trim();
    final hasPublicKey = _updatePublicKey.trim().isNotEmpty;

    final endpoints = <Uri>[];
    final apiOrigin = _parseUri(configuredOrigin);
    if (apiOrigin != null) {
      endpoints.add(apiOrigin.resolve('/api/releases/latest'));
    }

    if (repo.isNotEmpty) {
      if (hasPublicKey) {
        endpoints.add(
          Uri.parse(
              'https://github.com/$repo/releases/latest/download/latest.json'),
        );
      } else {
        endpoints
            .add(Uri.https('api.github.com', '/repos/$repo/releases/latest'));
      }
    }

    return endpoints;
  }

  bool _releaseHasUsableAssetForCurrentPlatform(
    Map<String, Object?> release, {
    required bool windowsManagedRuntimeAvailable,
    required List<String> androidSupportedAbis,
  }) {
    if (_shouldOfferAndroidManualFallback(
      release,
      androidSupportedAbis: androidSupportedAbis,
    )) {
      return true;
    }

    final manifestAsset = _matchManifestAssetForCurrentPlatformImpl(
      _platform,
      release,
      androidSupportedAbis: androidSupportedAbis,
    );
    if (manifestAsset != null) {
      return true;
    }

    final assets = _parseAssetsImpl(release['assets']);
    return _matchAssetForCurrentPlatformImpl(
          _platform,
          assets,
          windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
          androidSupportedAbis: androidSupportedAbis,
        ) !=
        null;
  }

  bool _shouldOfferAndroidManualFallback(
    Map<String, Object?> release, {
    required List<String> androidSupportedAbis,
  }) {
    if (_platform != AppUpdatePlatform.android ||
        androidSupportedAbis.isNotEmpty) {
      return false;
    }

    final manifestPlatforms = release['platforms'];
    if (manifestPlatforms is Map) {
      for (final key in manifestPlatforms.keys) {
        if (key is String && _isAndroidManualFallbackPlatformKey(key)) {
          return true;
        }
      }
    }

    final assets = _parseAssetsImpl(release['assets']);
    return assets.any(_isAndroidManualFallbackAssetCandidate);
  }

  Future<T> _withPreparedAsset<T>(
    AppUpdateAsset asset,
    Future<T> Function(Uri localUri) action,
  ) async {
    Directory? tempRoot;
    Uri localUri = asset.downloadUri;

    try {
      if (localUri.scheme == 'file') {
        final sourceFile = File(localUri.toFilePath());
        if (asset.sha256 != null) {
          await _verifyFileSha256(sourceFile, asset.sha256!);
        }
      } else {
        tempRoot = await Directory.systemTemp.createTemp('secondloop_asset_');
        final localPath =
            '${tempRoot.path}${Platform.pathSeparator}${_sanitizeAssetFileName(asset.name)}';
        final localFile = File(localPath);
        await _downloadToFile(asset.downloadUri, localFile);
        if (asset.sha256 != null) {
          await _verifyFileSha256(localFile, asset.sha256!);
        }
        localUri = localFile.uri;
      }

      return await action(localUri);
    } finally {
      if (tempRoot != null) {
        try {
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _verifyFileSha256(File file, String expectedHex) async {
    final actualHex = await _sha256FileHex(file);
    if (actualHex.toLowerCase() != expectedHex.trim().toLowerCase()) {
      throw StateError('update_asset_sha256_mismatch');
    }
  }

  Future<void> _verifySignedManifest(
      Uri manifestUri, List<int> bodyBytes) async {
    final publicKeyValue = _updatePublicKey.trim();
    if (publicKeyValue.isEmpty) {
      debugPrint(
        'WARNING: SECONDLOOP_UPDATE_PUBLIC_KEY is not set — '
        'skipping signature verification for $manifestUri',
      );
      return;
    }

    final sigUri = manifestUri.replace(path: '${manifestUri.path}.sig');
    final request = await _getUrlWithTimeout(sigUri);
    final response = await _closeRequestWithTimeout(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('signature_fetch_failed_${response.statusCode}',
          uri: sigUri);
    }

    final signatureBase64 =
        (await _readResponseTextWithTimeout(response)).trim();
    final signatureBytes = base64Decode(signatureBase64);
    final publicKey = SimplePublicKey(
      base64Decode(publicKeyValue),
      type: KeyPairType.ed25519,
    );
    final verified = await Ed25519().verify(
      bodyBytes,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    if (!verified) {
      throw const FormatException('invalid_update_manifest_signature');
    }
  }

  bool _shouldVerifyManifestSignature(Uri uri) {
    final normalizedPath = uri.path.toLowerCase();
    return normalizedPath.endsWith('latest.json') ||
        normalizedPath.endsWith('/api/releases/latest');
  }

  static String _sanitizeAssetFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (sanitized.isEmpty) {
      return 'secondloop-update.bin';
    }
    return sanitized;
  }

  static String? _normalizeLatestTag(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.startsWith('v') ? trimmed : 'v$trimmed';
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
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
    return _buildLinuxUpdaterScriptImpl(
      pid: pid,
      appDirPath: appDirPath,
      executablePath: executablePath,
      sourceDirPath: sourceDirPath,
      tempRootPath: tempRootPath,
    );
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

  Future<void> _recordEvent(
    UpdateEventType type, {
    String? currentVersion,
    String? latestTag,
    AppUpdateInstallMode? installMode,
    String? message,
  }) async {
    try {
      await _updateEventLogger.record(
        UpdateEventRecord(
          type: type,
          timestampUtc: DateTime.now().toUtc(),
          platform: _platform,
          currentVersion: currentVersion,
          latestTag: latestTag,
          installMode: installMode,
          message: message,
        ),
      );
    } catch (_) {}
  }

  Future<void> _recordFailure(
    UpdateEventType type,
    Object error, {
    String? currentVersion,
    String? latestTag,
    AppUpdateInstallMode? installMode,
  }) async {
    try {
      await _updateEventLogger.record(
        UpdateEventRecord(
          type: type,
          timestampUtc: DateTime.now().toUtc(),
          platform: _platform,
          currentVersion: currentVersion,
          latestTag: latestTag,
          installMode: installMode,
          message: error.toString(),
          failureCategory: classifyUpdateFailure(error),
        ),
      );
    } catch (_) {}
  }

  String _describeManualFallbackReason(AppUpdateAsset? asset) {
    if (asset == null) {
      return 'missing_platform_asset';
    }
    if (_platform == AppUpdatePlatform.windows &&
        _isWindowsVelopackPackageName(asset.name)) {
      return 'windows_runtime_unavailable';
    }
    if (_platform == AppUpdatePlatform.macos &&
        _isMacosManagedArchiveName(asset.name)) {
      return 'macos_install_location_unsupported_or_integrity_missing';
    }
    return 'manual_download_required';
  }

  bool _isAndroidApkInstallerCandidate(AppUpdateAsset? asset) {
    return _platform == AppUpdatePlatform.android &&
        asset != null &&
        isAndroidApkAssetForUpdate(asset);
  }

  bool _isAndroidManualFallbackPlatformKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'android' ||
        normalized == 'android-universal' ||
        normalized == 'android-arm64-v8a' ||
        normalized == 'android-arm64' ||
        normalized == 'android-armeabi-v7a' ||
        normalized == 'android-armv7' ||
        normalized == 'android-arm-v7a';
  }

  bool _isAndroidManualFallbackAssetCandidate(AppUpdateAsset asset) {
    if (!_isAndroidApkAssetImpl(asset)) {
      return false;
    }

    if (_extractLeadingAndroidAbiImpl(asset.name) != null) {
      return true;
    }

    return _isAndroidUniversalApkNameImpl(asset.name);
  }
}
