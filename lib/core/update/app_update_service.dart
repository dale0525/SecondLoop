import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_helpers.dart';
import 'app_update_architecture.dart';
import 'app_update_models.dart';
import 'app_update_platform.dart';
import 'app_update_resolution.dart';
import 'linux/linux_update_script.dart';
import 'macos/macos_update_client.dart';
import 'update_event_log.dart';
import 'windows/velopack_update_client.dart';

export 'app_update_models.dart';
export 'linux/linux_update_script.dart';

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

typedef AppUpdateReleaseJsonFetcher = Future<Map<String, Object?>> Function(
  Uri uri,
);
typedef AppRuntimeVersionLoader = Future<AppRuntimeVersion> Function();

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
    String? currentArchitectureOverride,
    bool? allowHttpUpdateUriOverride,
    bool? allowFileUpdateUriOverride,
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
        _currentArchitectureOverride = currentArchitectureOverride,
        _allowHttpUpdateUriOverride = allowHttpUpdateUriOverride,
        _allowFileUpdateUriOverride = allowFileUpdateUriOverride;

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
  final String? _currentArchitectureOverride;
  final bool? _allowHttpUpdateUriOverride;
  final bool? _allowFileUpdateUriOverride;

  AppUpdatePlatform get _platform =>
      _platformOverride ?? detectAppUpdatePlatform();

  bool get _isReleaseMode => _releaseModeOverride ?? kReleaseMode;
  String get _releaseApiOrigin =>
      _releaseApiOriginOverride ?? _defaultReleaseApiOrigin;
  String get _releaseRepo => _releaseRepoOverride ?? _defaultReleaseRepo;
  String get releaseRepo => _releaseRepo;
  String get _updatePublicKey =>
      _updatePublicKeyOverride ?? _defaultUpdatePublicKey;
  Duration get _networkTimeout =>
      _networkTimeoutOverride ?? _defaultUpdateNetworkTimeout;
  Uri get fallbackReleasePageUri => _buildFallbackReleasePageUri();
  bool get _allowHttpUpdateUris =>
      _allowHttpUpdateUriOverride ?? !_isReleaseMode;
  bool get _allowFileUpdateUris =>
      _allowFileUpdateUriOverride ?? !_isReleaseMode;
  String get _currentArchitecture => normalizeArchitectureLabel(
        _currentArchitectureOverride ?? currentArchitectureForUpdates(),
      );
  String? get _windowsAppId {
    final stagedClient = _resolvedWindowsStagedUpdateClient;
    if (stagedClient == null) {
      return null;
    }
    final value = stagedClient.appId.trim();
    return value.isEmpty ? null : value;
  }

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

    final latestTag = normalizeLatestTag(
      readUpdateString(release, 'tag_name') ??
          readUpdateString(release, 'version'),
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

    if (parseComparableAppVersion(latestTag) == null ||
        parseComparableAppVersion(currentVersion) == null) {
      await _recordFailure(
        UpdateEventType.checkFailed,
        'unsupported_version_format',
        currentVersion: runtimeVersion.display,
      );
      return AppUpdateCheckResult(
        currentVersion: runtimeVersion.display,
        errorMessage: 'unsupported_version_format',
      );
    }

    final releasePageUri = parseUpdateUri(
          readUpdateString(release, 'release_page_url'),
          allowHttp: _allowHttpUpdateUris,
          allowFile: _allowFileUpdateUris,
        ) ??
        parseUpdateUri(
          readUpdateString(release, 'html_url'),
          allowHttp: _allowHttpUpdateUris,
          allowFile: _allowFileUpdateUris,
        ) ??
        _buildFallbackReleasePageUri();

    if (compareReleaseTagWithCurrentVersion(latestTag, currentVersion) <= 0) {
      await _recordEvent(
        UpdateEventType.checkSucceeded,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        message: 'up_to_date',
      );
      return AppUpdateCheckResult(currentVersion: runtimeVersion.display);
    }

    final windowsStagedClient = _resolvedWindowsStagedUpdateClient;
    final windowsManagedRuntimeAvailable =
        windowsStagedClient != null && windowsStagedClient.isAvailable();
    final effectiveWindowsAppId = _windowsAppId;
    final macosManagedClient = _resolvedMacosManagedUpdateClient;
    final macosManagedInstallSupported = macosManagedClient != null &&
        macosManagedClient.isSupportedInstallLocation();

    final manifestAsset = matchManifestAssetForCurrentPlatform(
      _platform,
      release,
      currentArchitecture: _currentArchitecture,
      allowHttp: _allowHttpUpdateUris,
      allowFile: _allowFileUpdateUris,
      windowsAppId: effectiveWindowsAppId,
    );
    final assets = _parseAssets(release['assets']);
    final preferredAsset = manifestAsset ??
        matchAssetForCurrentPlatform(
          _platform,
          assets,
          windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
          currentArchitecture: _currentArchitecture,
          windowsAppId: effectiveWindowsAppId,
        );
    final installMode = resolveInstallMode(
      _platform,
      asset: preferredAsset,
      isReleaseMode: _isReleaseMode,
      windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
      macosManagedInstallSupported: macosManagedInstallSupported,
      windowsAppId: effectiveWindowsAppId,
    );
    final matchedAsset = installMode == AppUpdateInstallMode.externalDownload
        ? selectExternalDownloadAsset(
            _platform,
            preferredAsset: preferredAsset,
            assets: assets,
            currentArchitecture: _currentArchitecture,
            windowsAppId: effectiveWindowsAppId,
          )
        : preferredAsset;
    final sawWindowsIdentityMismatch = _platform == AppUpdatePlatform.windows &&
        releaseContainsWindowsIdentityMismatch(
          release,
          windowsAppId: effectiveWindowsAppId,
        );
    final manualFallbackReason = describeManualFallbackReason(
      _platform,
      preferredAsset ?? matchedAsset,
      isReleaseMode: _isReleaseMode,
      windowsManagedRuntimeAvailable: windowsManagedRuntimeAvailable,
      macosManagedInstallSupported: macosManagedInstallSupported,
      windowsAppId: effectiveWindowsAppId,
      sawWindowsIdentityMismatch: sawWindowsIdentityMismatch,
    );

    await _recordEvent(
      UpdateEventType.updateAvailable,
      currentVersion: runtimeVersion.display,
      latestTag: latestTag,
      installMode: installMode,
      message: matchedAsset?.name ?? manualFallbackReason,
    );
    await _recordEvent(
      UpdateEventType.checkSucceeded,
      currentVersion: runtimeVersion.display,
      latestTag: latestTag,
      installMode: installMode,
      message: 'update_available',
    );
    if (installMode == AppUpdateInstallMode.externalDownload) {
      await _recordEvent(
        UpdateEventType.manualFallback,
        currentVersion: runtimeVersion.display,
        latestTag: latestTag,
        installMode: installMode,
        message: manualFallbackReason,
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
        final targetVersion =
            normalizeLatestTag(update.latestTag)?.replaceFirst(
                  RegExp(r'^v'),
                  '',
                ) ??
                update.latestTag.replaceFirst(RegExp(r'^v'), '');
        final pendingVersion = stagedClient.pendingUpdateVersion();
        final pendingPackagePath = stagedClient.pendingUpdatePackagePath();
        final hasVerifiedReusablePendingUpdate =
            stagedClient.hasPendingUpdate() &&
                pendingVersion != null &&
                sameNormalizedVersion(pendingVersion, targetVersion) &&
                await _canReuseVerifiedPendingWindowsUpdate(
                  asset: asset,
                  pendingPackagePath: pendingPackagePath,
                );
        if (hasVerifiedReusablePendingUpdate) {
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

      await _withPreparedAsset(asset, (localUri) async {
        final tempRoot =
            await Directory.systemTemp.createTemp('secondloop_update_');
        try {
          final archiveFile = File(localUri.toFilePath());
          final extractedDir = Directory('${tempRoot.path}/payload');
          await extractedDir.create(recursive: true);

          await extractFileToDisk(archiveFile.path, extractedDir.path);

          final sourceDir = resolveExtractedSourceDir(extractedDir, platform);
          final executablePath =
              File(Platform.resolvedExecutable).absolute.path;
          final appDirPath = File(executablePath).parent.path;

          final script = File('${tempRoot.path}/apply_update.sh');
          await script.writeAsString(
            buildLinuxUpdaterScript(
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
            await _deleteDirectoryIfExists(tempRoot);
          } catch (_) {}
          rethrow;
        }
      });
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
      if (update.installMode != AppUpdateInstallMode.stagedNextLaunch &&
          !canStageSilentlyForNextLaunch(update)) {
        throw StateError('staged_update_not_supported');
      }
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

  Future<PendingUpdateStartupResult> applyPendingUpdateOnStartup() async {
    if (_platform != AppUpdatePlatform.windows) {
      return const PendingUpdateStartupResult.noPendingUpdate();
    }
    final stagedClient = _resolvedWindowsStagedUpdateClient;
    if (stagedClient == null || !stagedClient.isAvailable()) {
      return const PendingUpdateStartupResult.noPendingUpdate();
    }
    try {
      final result = await stagedClient.applyPendingOnStartup(waitPid: pid);
      if (!result.hasNoPendingUpdate && !result.isProbeInconclusive) {
        await _recordEvent(UpdateEventType.pendingApplyStarted);
      }
      if (result.didLaunchUpdater) {
        await _recordEvent(UpdateEventType.pendingApplyDispatched);
        _exitProcess(0);
      }
      if (result.isUpdateInProgress) {
        _exitProcess(0);
      }
      return result;
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

  bool canStageSilentlyForNextLaunch(AppUpdateAvailability update) {
    if (_platform != AppUpdatePlatform.windows) {
      return false;
    }
    final stagedClient = _resolvedWindowsStagedUpdateClient;
    final supportedInstallMode =
        update.installMode == AppUpdateInstallMode.seamlessRestart ||
            update.installMode == AppUpdateInstallMode.stagedNextLaunch;
    final asset = update.asset;
    final appId = _windowsAppId;
    final isMatchingWindowsPackage = asset != null &&
        ((appId != null && appId.isNotEmpty)
            ? isWindowsVelopackPackageNameForApp(asset.name, appId: appId)
            : isWindowsVelopackPackageName(asset.name));
    return isMatchingWindowsPackage &&
        supportedInstallMode &&
        stagedClient != null &&
        stagedClient.isAvailable();
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
    if (_isSignedManifestUri(uri)) {
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

    final endpoints = <Uri>[];
    final allowHttp = _allowHttpUpdateUris;
    final allowFile = _allowFileUpdateUris;
    final parsedApiOrigin = parseUpdateUri(
      configuredOrigin,
      allowHttp: allowHttp,
      allowFile: allowFile,
    );
    if (parsedApiOrigin != null) {
      final normalizedPath = parsedApiOrigin.path.endsWith('/')
          ? parsedApiOrigin.path
          : '${parsedApiOrigin.path}/';
      endpoints.add(
        parsedApiOrigin.replace(path: '${normalizedPath}api/releases/latest'),
      );
    }

    if (repo.isNotEmpty) {
      endpoints.add(
        Uri.parse(
            'https://github.com/$repo/releases/latest/download/latest.json'),
      );
      endpoints
          .add(Uri.https('api.github.com', '/repos/$repo/releases/latest'));
    }

    return endpoints;
  }

  Uri _buildFallbackReleasePageUri() {
    final origin = parseUpdateUri(
      _releaseApiOrigin.trim(),
      allowHttp: _allowHttpUpdateUris,
      allowFile: _allowFileUpdateUris,
    );
    if (origin != null) {
      final normalizedPath =
          origin.path.endsWith('/') ? origin.path : '${origin.path}/';
      return origin.replace(path: '${normalizedPath}releases/latest');
    }

    final repo = _releaseRepo.trim();
    if (repo.isEmpty) {
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
      final sha256 = item['sha256'];
      if (name is! String || url is! String) continue;
      final uri = parseUpdateUri(
        url,
        allowHttp: _allowHttpUpdateUris,
        allowFile: _allowFileUpdateUris,
      );
      if (uri == null) continue;
      parsed.add(
        AppUpdateAsset(
          name: name,
          downloadUri: uri,
          sha256: sha256 is String && sha256.trim().isNotEmpty
              ? sha256.trim()
              : null,
        ),
      );
    }

    return parsed;
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
            '${tempRoot.path}${Platform.pathSeparator}${sanitizeUpdateAssetFileName(asset.name)}';
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
          await _deleteDirectoryIfExists(tempRoot);
        } catch (_) {}
      }
    }
  }

  Future<bool> _canReuseVerifiedPendingWindowsUpdate({
    required AppUpdateAsset asset,
    required String? pendingPackagePath,
  }) async {
    if (pendingPackagePath == null || pendingPackagePath.trim().isEmpty) {
      return false;
    }
    final pendingFile = File(pendingPackagePath);
    if (!pendingFile.existsSync()) {
      return false;
    }
    final expectedSha = asset.sha256?.trim();
    if (expectedSha == null || expectedSha.isEmpty) {
      return false;
    }
    final actualSha = await _sha256FileHex(pendingFile);
    return actualSha.toLowerCase() == expectedSha.toLowerCase();
  }

  Future<void> _deleteDirectoryIfExists(Directory dir) async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      if (!dir.existsSync()) {
        return;
      }
      try {
        await dir.delete(recursive: true);
        return;
      } catch (_) {
        if (attempt == 19) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
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

  bool _isSignedManifestUri(Uri uri) {
    final normalizedPath = uri.path.toLowerCase();
    return normalizedPath.endsWith('latest.json') ||
        normalizedPath.endsWith('/api/releases/latest');
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
}

Future<String> sha256FileHexForTest(File file) => _sha256FileHex(file);

Future<String> _sha256FileHex(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  final digest = await sink.hash();
  return _hexEncodeBytes(digest.bytes);
}

String _hexEncodeBytes(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
