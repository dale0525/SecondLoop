import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

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

void main() {
  group('compareReleaseTagWithCurrentVersion', () {
    test('treats higher release tag as update', () {
      expect(compareReleaseTagWithCurrentVersion('v1.2.0', '1.1.9'),
          greaterThan(0));
    });

    test('ignores fourth tag segment for compatibility', () {
      expect(compareReleaseTagWithCurrentVersion('v1.2.3.9', '1.2.3'), 0);
    });

    test('treats same version as up to date', () {
      expect(compareReleaseTagWithCurrentVersion('v2.0.0', '2.0.0'), 0);
    });
  });

  group('AppUpdateService.checkForUpdates', () {
    test('returns external Windows MSI update when matching asset exists',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '42'),
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
          ],
        },
      );

      final result = await service.checkForUpdates();
      final update = result.update;

      expect(result.errorMessage, isNull);
      expect(update, isNotNull);
      expect(update!.latestTag, 'v1.1.0');
      expect(update.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        update.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test(
        'prefers MSI manual Windows update even when Velopack runtime is available',
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
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(
        result.update!.installMode,
        AppUpdateInstallMode.externalDownload,
      );
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test(
        'returns external Windows MSI installer when staged runtime is unavailable',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '89'),
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
              'name': 'SecondLoop-windows-x64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/legacy.msi',
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
      expect(
        result.update!.installMode,
        AppUpdateInstallMode.externalDownload,
      );
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test('uses MSI asset directly when only MSI asset exists on Windows',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '90'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-windows-x64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/legacy.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(
        result.update!.installMode,
        AppUpdateInstallMode.externalDownload,
      );
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/legacy.msi',
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
      final update = result.update;

      expect(update, isNotNull);
      expect(update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        update.downloadUri.toString(),
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
      expect(attempted.last.toString(), contains('api.github.com/repos/'));
    });

    test('skips custom release origin when configured as empty', () async {
      final attempted = <Uri>[];
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        releaseApiOriginOverride: '',
        releaseRepoOverride: 'dale0525/SecondLoop',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '10'),
        releaseJsonFetcher: (uri) async {
          attempted.add(uri);
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
      expect(attempted.length, 1);
      expect(
        attempted.single.toString(),
        contains('api.github.com/repos/dale0525/SecondLoop/releases/latest'),
      );
    });

    test('falls back to release page when MSI asset is missing on Windows',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '11'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'com.secondloop.secondloop-1.1.0-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win.nupkg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(
        result.update!.installMode,
        AppUpdateInstallMode.externalDownload,
      );
      expect(
        result.update!.downloadUri.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    });
  });

  group('AppUpdateService.applyPendingUpdateOnStartup', () {
    test('does not apply pending Windows updates when runtime is available',
        () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
      );

      await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 0);
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
    test('throws when asked to restart into staged Windows update', () async {
      final stagedClient = _FakeWindowsStagedUpdateClient(available: true);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        processExit: (code) => exitedCode = code,
      );

      await expectLater(
        service.applyStagedUpdateAndRestart(),
        throwsA(isA<StateError>()),
      );

      expect(stagedClient.applyPendingAndRestartCalls, 0);
      expect(exitedCode, -1);
    });
  });
}
