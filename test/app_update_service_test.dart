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

class _FakeWindowsStagedUpdateClient implements WindowsStagedUpdateClient {
  _FakeWindowsStagedUpdateClient({required this.available});

  final bool available;
  final List<Uri> stagedAssets = <Uri>[];
  final List<Uri> installedAssets = <Uri>[];
  int applyPendingCalls = 0;
  int applyPendingAndRestartCalls = 0;
  int installCalls = 0;

  @override
  bool isAvailable() => available;

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {
    stagedAssets.add(assetDownloadUri);
  }

  @override
  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(assetDownloadUri);
  }

  @override
  Future<void> applyPendingOnStartup() async {
    applyPendingCalls += 1;
  }

  @override
  Future<void> applyPendingAndRestart({required int waitPid}) async {
    applyPendingAndRestartCalls += 1;
  }
}

class _FakeMacosManagedUpdateClient implements MacosManagedUpdateClient {
  _FakeMacosManagedUpdateClient({required this.supportedInstallLocation});

  final bool supportedInstallLocation;
  final List<Uri> installedAssets = <Uri>[];
  int installCalls = 0;

  @override
  bool isSupportedInstallLocation() => supportedInstallLocation;

  @override
  Future<void> installArchiveAndRestart(
    Uri archiveUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(archiveUri);
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
              'package_url': 'https://cdn.example.com/SecondLoop-1.1.0.nupkg',
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
        'https://cdn.example.com/SecondLoop-1.1.0.nupkg',
      );
      expect(result.update!.asset?.sha256, 'abc123');
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
              'package_url': 'https://cdn.example.com/SecondLoop-1.1.0.nupkg',
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

  group('AppUpdateService.installAndRestart', () {
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
    test('applies pending Windows updates when runtime is available', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
      );

      await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 1);
    });

    test('skips apply when staged runtime is unavailable', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
      );

      await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 0);
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
