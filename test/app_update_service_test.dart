import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/macos/macos_update_client.dart';
import 'package:secondloop/core/update/update_event_log.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

class _InMemoryUpdateEventLogger implements UpdateEventLogger {
  final List<UpdateEventRecord> records = <UpdateEventRecord>[];

  @override
  Future<void> record(UpdateEventRecord record) async {
    records.add(record);
  }

  @override
  Future<List<UpdateEventRecord>> readRecent() async => records;
}

class _ThrowingUpdateEventLogger implements UpdateEventLogger {
  _ThrowingUpdateEventLogger({required this.failOnType});

  final UpdateEventType failOnType;
  final List<UpdateEventRecord> records = <UpdateEventRecord>[];

  @override
  Future<void> record(UpdateEventRecord record) async {
    if (record.type == failOnType) {
      throw StateError('logger_failed_${record.type.name}');
    }
    records.add(record);
  }

  @override
  Future<List<UpdateEventRecord>> readRecent() async => records;
}

class _FakeWindowsStagedUpdateClient implements WindowsStagedUpdateClient {
  _FakeWindowsStagedUpdateClient({
    required this.available,
    this.pendingUpdateAvailable = false,
    this.pendingApplyStartupResult =
        const PendingUpdateStartupResult.noPendingUpdate(),
    this.onStageAsset,
    this.onInstallAsset,
  });

  final bool available;
  final bool pendingUpdateAvailable;
  final PendingUpdateStartupResult pendingApplyStartupResult;
  final Future<void> Function(Uri assetDownloadUri)? onStageAsset;
  final Future<void> Function(Uri assetDownloadUri)? onInstallAsset;
  final List<Uri> stagedAssets = <Uri>[];
  final List<Uri> installedAssets = <Uri>[];
  int applyPendingCalls = 0;
  int applyPendingAndRestartCalls = 0;
  int installCalls = 0;
  int isAvailableCalls = 0;
  int? lastStartupWaitPid;

  @override
  bool isAvailable() {
    isAvailableCalls += 1;
    return available;
  }

  @override
  bool hasPendingUpdate() {
    return pendingUpdateAvailable;
  }

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {
    stagedAssets.add(assetDownloadUri);
    await onStageAsset?.call(assetDownloadUri);
  }

  @override
  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(assetDownloadUri);
    await onInstallAsset?.call(assetDownloadUri);
  }

  @override
  Future<PendingUpdateStartupResult> applyPendingOnStartup({
    required int waitPid,
  }) async {
    applyPendingCalls += 1;
    lastStartupWaitPid = waitPid;
    return pendingApplyStartupResult;
  }

  @override
  Future<void> applyPendingAndRestart({required int waitPid}) async {
    applyPendingAndRestartCalls += 1;
  }
}

class _FakeMacosManagedUpdateClient implements MacosManagedUpdateClient {
  _FakeMacosManagedUpdateClient({
    required this.supportedInstallLocation,
    this.onInstallArchive,
  });

  final bool supportedInstallLocation;
  final Future<void> Function(Uri archiveUri)? onInstallArchive;
  final List<Uri> installedAssets = <Uri>[];
  int installCalls = 0;
  int isSupportedInstallLocationCalls = 0;

  @override
  bool isSupportedInstallLocation() {
    isSupportedInstallLocationCalls += 1;
    return supportedInstallLocation;
  }

  @override
  Future<void> installArchiveAndRestart(
    Uri archiveUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(archiveUri);
    await onInstallArchive?.call(archiveUri);
  }
}

void main() {
  group('compareReleaseTagWithCurrentVersion', () {
    test('treats higher release tag as update', () {
      expect(
        compareReleaseTagWithCurrentVersion('v1.2.0', '1.1.9'),
        greaterThan(0),
      );
    });

    test('ignores fourth tag segment for compatibility', () {
      expect(compareReleaseTagWithCurrentVersion('v1.2.3.9', '1.2.3'), 0);
    });

    test('treats same version as up to date', () {
      expect(compareReleaseTagWithCurrentVersion('v2.0.0', '2.0.0'), 0);
    });
  });

  group('AppUpdateService.checkForUpdates', () {
    test('returns seamless Windows nupkg update when runtime is available',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '42'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'windows-x64': {
              'install_mode': 'velopack',
              'package_url':
                  'https://cdn.example.com/com.secondloop.secondloop-1.1.0-full.nupkg',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.1.0');
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/com.secondloop.secondloop-1.1.0-full.nupkg',
      );
      expect(result.update!.asset?.sha256, 'abc123');
    });

    test('checks Windows managed runtime once when picking release asset',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-win.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win.msi',
            },
            {
              'name': 'com.secondloop.secondloop-1.1.0-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win.nupkg',
              'sha256': 'abc123',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/win.nupkg',
      );
      expect(stagedClient.isAvailableCalls, 1);
    });

    test('falls back to external MSI when Windows runtime is unavailable',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-win.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win.msi',
            },
            {
              'name': 'com.secondloop.secondloop-1.1.0-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win.nupkg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test('ignores delta nupkg assets and falls back to MSI installers',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'com.secondloop.secondloop-1.1.0-delta.nupkg',
              'browser_download_url': 'https://cdn.example.com/win-delta.nupkg',
            },
            {
              'name': 'SecondLoop-win.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-win.msi');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test('returns seamless macOS archive update for supported install paths',
        () async {
      final macosClient =
          _FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'macos-universal': {
              'install_mode': 'app-tar-gz',
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-v1.1.0.app.tar.gz',
              'sha256': 'def456',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-v1.1.0.app.tar.gz',
      );
      expect(result.update!.asset?.sha256, 'def456');
    });

    test('falls back to external download on macOS for unsupported paths',
        () async {
      final macosClient =
          _FakeMacosManagedUpdateClient(supportedInstallLocation: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'macos-universal': {
              'install_mode': 'app-tar-gz',
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-v1.1.0.app.tar.gz',
              'sha256': 'def456',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-v1.1.0.app.tar.gz',
      );
    });

    test('requires sha256 for seamless Linux archive installs', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'linux-x64': {
              'install_mode': 'bundle-tar-gz',
              'archive_url':
                  'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
    });

    test('falls back to external release page when no platform asset exists',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-win-Setup.exe',
              'browser_download_url': 'https://cdn.example.com/setup.exe',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        result.update!.downloadUri.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    });

    test('tries fallback endpoint when first endpoint fails', () async {
      final attempted = <Uri>[];
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        releaseApiOriginOverride: 'https://secondloop.app',
        releaseRepoOverride: 'dale0525/SecondLoop',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async {
          attempted.add(uri);
          if (attempted.length == 1) {
            throw StateError('network_down');
          }
          return {
            'tag_name': 'v1.0.0',
            'html_url':
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.0',
            'assets': const [],
          };
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, isNull);
      expect(attempted.length, 2);
      expect(attempted.first.toString(), contains('/api/releases/latest'));
      expect(attempted.last.toString(),
          contains('/releases/latest/download/latest.json'));
    });

    test('records update available and manual fallback events', () async {
      final logger = _InMemoryUpdateEventLogger();
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'platforms': {
            'windows-x64': {
              'package_url':
                  'https://cdn.example.com/com.secondloop.secondloop-1.1.0-full.nupkg',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(
        logger.records
            .any((entry) => entry.type == UpdateEventType.updateAvailable),
        isTrue,
      );
      expect(
        logger.records.any((entry) =>
            entry.type == UpdateEventType.manualFallback &&
            entry.message == 'windows_runtime_unavailable'),
        isTrue,
      );
    });
  });

  group('AppUpdateService.downloaded asset handoff', () {
    test('cleans temporary downloaded asset after Windows staging', () async {
      String? stagedPath;
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        onStageAsset: (assetDownloadUri) async {
          stagedPath = assetDownloadUri.toFilePath();
          expect(File(stagedPath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
      );

      await service.stageUpdateForNextLaunch(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.stagedNextLaunch,
          asset: AppUpdateAsset(
            name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
            downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          ),
        ),
      );

      expect(stagedPath, isNotNull);
      expect(Directory(File(stagedPath!).parent.path).existsSync(), isFalse);
    });

    test('cleans temporary downloaded asset when Windows handoff sha256 fails',
        () async {
      final before = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_asset_'))
          .map((dir) => dir.path)
          .toSet();
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'tampered-nupkg',
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
              downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
              sha256: 'deadbeef',
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_asset_'))
          .map((dir) => dir.path)
          .toSet();
      expect(after, before);
    });

    test('cleans temporary downloaded asset after Windows installer handoff',
        () async {
      String? packagePath;
      var exitedCode = -1;
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        onInstallAsset: (assetDownloadUri) async {
          packagePath = assetDownloadUri.toFilePath();
          expect(File(packagePath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      await service.installAndRestart(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.seamlessRestart,
          asset: AppUpdateAsset(
            name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
            downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          ),
        ),
      );

      expect(exitedCode, 0);
      expect(packagePath, isNotNull);
      expect(Directory(File(packagePath!).parent.path).existsSync(), isFalse);
    });

    test('cleans temporary downloaded asset after macOS updater handoff',
        () async {
      String? archivePath;
      var exitedCode = -1;
      final macosClient = _FakeMacosManagedUpdateClient(
        supportedInstallLocation: true,
        onInstallArchive: (archiveUri) async {
          archivePath = archiveUri.toFilePath();
          expect(File(archivePath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        macosManagedUpdateClient: macosClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'macos-archive',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      await service.installAndRestart(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.seamlessRestart,
          asset: AppUpdateAsset(
            name: 'SecondLoop-macos-v1.1.0.app.tar.gz',
            downloadUri:
                Uri.parse('https://cdn.example.com/SecondLoop-macos.tar.gz'),
          ),
        ),
      );

      expect(exitedCode, 0);
      expect(archivePath, isNotNull);
      expect(Directory(File(archivePath!).parent.path).existsSync(), isFalse);
    });
  });

  group('AppUpdateService.installAndRestart', () {
    test('applies staged Windows update without re-downloading', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: true,
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => throw StateError('should_not_download:$uri'),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.installCalls, 0);
      expect(stagedClient.applyPendingAndRestartCalls, 1);
      expect(exitedCode, 0);
    });

    test('delegates Windows install to Velopack and exits', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final logger = _InMemoryUpdateEventLogger();
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('file:///tmp/SecondLoop-1.1.0.nupkg'),
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.installCalls, 1);
      expect(stagedClient.installedAssets.single.toString(),
          'file:///tmp/SecondLoop-1.1.0.nupkg');
      expect(exitedCode, 0);
      expect(
        logger.records
            .any((entry) => entry.type == UpdateEventType.installDispatched),
        isTrue,
      );
    });

    test('verifies sha256 before Linux seamless install', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'tampered-linux-archive',
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
              downloadUri: Uri.parse(
                'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
              ),
              sha256: 'abc123',
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cleans Linux tempRoot when install throws before script handoff',
        () async {
      const body = 'not-a-valid-tar-archive';
      final tempHashDir = await Directory.systemTemp.createTemp('linux_hash_');
      addTearDown(() => tempHashDir.delete(recursive: true));
      final hashFile = File('${tempHashDir.path}/payload.tar.gz');
      await hashFile.writeAsString(body);
      final expectedSha = await sha256FileHexForTest(hashFile);
      final before = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_update_'))
          .map((dir) => dir.path)
          .toSet();
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: body,
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
              downloadUri: Uri.parse(
                'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
              ),
              sha256: expectedSha,
            ),
          ),
        ),
        throwsA(anything),
      );

      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_update_'))
          .map((dir) => dir.path)
          .toSet();
      final created = after.difference(before);
      for (final path in created) {
        try {
          final dir = Directory(path);
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
      if (Platform.isWindows) {
        return;
      }
      expect(after, before);
    });

    test('delegates macOS install to managed client and exits', () async {
      final macosClient =
          _FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        macosManagedUpdateClient: macosClient,
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'SecondLoop-macos-v1.1.0.app.tar.gz',
          downloadUri:
              Uri.parse('file:///tmp/SecondLoop-macos-v1.1.0.app.tar.gz'),
        ),
      );

      await service.installAndRestart(update);

      expect(macosClient.installCalls, 1);
      expect(macosClient.installedAssets.single.toString(),
          'file:///tmp/SecondLoop-macos-v1.1.0.app.tar.gz');
      expect(exitedCode, 0);
    });
  });

  group('AppUpdateService.applyPendingUpdateOnStartup', () {
    test('records pending apply dispatch before exiting current process',
        () async {
      final logger = _InMemoryUpdateEventLogger();
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateDispatched(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 1);
      expect(stagedClient.lastStartupWaitPid, pid);
      expect(applied.status, PendingUpdateStartupStatus.dispatched);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isTrue,
      );
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplySucceeded,
        ),
        isFalse,
      );
    });

    test('still exits when dispatch event logging fails', () async {
      final logger = _ThrowingUpdateEventLogger(
        failOnType: UpdateEventType.pendingApplyDispatched,
      );
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateDispatched(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(applied.status, PendingUpdateStartupStatus.dispatched);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyStarted,
        ),
        isTrue,
      );
    });

    test('skips dispatch event when no pending update is available', () async {
      final logger = _InMemoryUpdateEventLogger();
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: false,
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 1);
      expect(applied.status, PendingUpdateStartupStatus.none);
      expect(exitedCode, -1);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isFalse,
      );
    });

    test('skips apply when staged runtime is unavailable', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 0);
      expect(applied.status, PendingUpdateStartupStatus.none);
      expect(exitedCode, -1);
    });

    test('exits when pending Windows apply is already in progress', () async {
      final logger = _InMemoryUpdateEventLogger();
      final stagedClient = _FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateInProgress(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(applied.status, PendingUpdateStartupStatus.inProgress);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isFalse,
      );
    });
  });

  group('AppUpdateService.applyStagedUpdateAndRestart', () {
    test('restarts into staged Windows update when runtime is available',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        processExit: (code) => exitedCode = code,
      );

      await service.applyStagedUpdateAndRestart();

      expect(stagedClient.applyPendingAndRestartCalls, 1);
      expect(exitedCode, 0);
    });
  });
}

final class _FakeHttpResponse {
  const _FakeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.handler});

  final _FakeHttpResponse Function(Uri uri) handler;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final response = handler(url);
    return _FakeHttpClientRequest(
      response: _FakeHttpClientResponse(
        statusCode: response.statusCode,
        body: response.body,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.response});

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required String body})
      : _stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);

  final Stream<List<int>> _stream;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
