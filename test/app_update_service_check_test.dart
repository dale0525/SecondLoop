import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/update_event_log.dart';
import 'support/app_update_service_test_support.dart';

void main() {
  group('AppUpdateService.checkForUpdates', () {
    test('returns seamless Windows nupkg update when runtime is available',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
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

    test(
        'returns staged-next-launch update when manifest explicitly requests it',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
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
              'install_mode': 'staged-next-launch',
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
      expect(result.update!.installMode, AppUpdateInstallMode.stagedNextLaunch);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/com.secondloop.secondloop-1.1.0-full.nupkg',
      );
    });

    test('checks Windows managed runtime once when picking release asset',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
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

    test(
        'prefers matching Windows velopack package over mismatched arm64 asset',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentArchitectureOverride: 'x86_64',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'com.secondloop.secondloop-1.1.0-arm64-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win-arm64.nupkg',
              'sha256': 'arm64sha',
            },
            {
              'name': 'com.secondloop.secondloop-1.1.0-x64-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win-x64.nupkg',
              'sha256': 'x64sha',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.asset?.downloadUri.toString(),
        'https://cdn.example.com/win-x64.nupkg',
      );
      expect(result.update!.asset?.sha256, 'x64sha');
    });

    test('falls back to external MSI when Windows runtime is unavailable',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
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

    test('prefers x64 MSI fallback over arm64 installer on Windows x64',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentArchitectureOverride: 'x86_64',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-win-arm64-v1.1.0.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win-arm64-v1.1.0.msi',
            },
            {
              'name': 'SecondLoop-win-x64-v1.1.0.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win-x64-v1.1.0.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-win-x64-v1.1.0.msi');
    });

    test('does not offer arm64-only Windows MSI on x64', () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentArchitectureOverride: 'x86_64',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '88'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-win-arm64-v1.1.0.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win-arm64-v1.1.0.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset, isNull);
      expect(
        result.update!.downloadUri.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    });

    test('ignores delta nupkg assets and falls back to MSI installers',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
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
          FakeMacosManagedUpdateClient(supportedInstallLocation: true);
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
          FakeMacosManagedUpdateClient(supportedInstallLocation: false);
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
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
      expect(result.update!.asset, isNull);
    });

    test(
        'falls back to release page when Windows external download has no MSI asset',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
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
              'name': 'com.secondloop.secondloop-1.1.0-full.nupkg',
              'browser_download_url': 'https://cdn.example.com/win.nupkg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset, isNull);
      expect(
        result.update!.downloadUri.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    });

    test('prefers current macOS architecture over mismatched manifest entry',
        () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        currentArchitectureOverride: 'x86_64',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'darwin-aarch64': {
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.app.tar.gz',
              'sha256': 'arm64sha',
            },
            'darwin-x86_64': {
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.app.tar.gz',
              'sha256': 'x64sha',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.downloadUri.toString(),
          'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.app.tar.gz');
      expect(result.update!.asset?.sha256, 'x64sha');
    });

    test('prefers matching macOS managed archive over mismatched arm64 asset',
        () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        currentArchitectureOverride: 'x86_64',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-macos-arm64-v1.1.0.app.tar.gz',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.app.tar.gz',
              'sha256': 'arm64sha',
            },
            {
              'name': 'SecondLoop-macos-x64-v1.1.0.app.tar.gz',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.app.tar.gz',
              'sha256': 'x64sha',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.asset?.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.app.tar.gz',
      );
      expect(result.update!.asset?.sha256, 'x64sha');
    });

    test('does not fall back from x64 macOS to arm64-only manifest entry',
        () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        currentArchitectureOverride: 'x86_64',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'darwin-aarch64': {
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.app.tar.gz',
              'sha256': 'arm64sha',
            },
          },
          'assets': [
            {
              'name': 'SecondLoop-macos-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-macos-v1.1.0.dmg');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
      );
    });

    test('prefers x64 macOS manual fallback over arm64-only archive assets',
        () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        currentArchitectureOverride: 'x86_64',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-macos-arm64-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.dmg',
            },
            {
              'name': 'SecondLoop-macos-x64-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.dmg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-macos-x64-v1.1.0.dmg');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.dmg',
      );
    });

    test('prefers generic macOS asset when architecture is unknown', () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '21'),
        currentArchitectureOverride: 'mystery-cpu',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-macos-arm64-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.dmg',
            },
            {
              'name': 'SecondLoop-macos-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
            },
            {
              'name': 'SecondLoop-macos-x64-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-x64-v1.1.0.dmg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-macos-v1.1.0.dmg');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
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

    test('matches linux x86_64 assets when manifest is missing', () async {
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
              'name': 'SecondLoop-linux-x86_64-v1.1.0.tar.gz',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-linux-x86_64-v1.1.0.tar.gz',
              'sha256': 'linuxsha',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.seamlessRestart);
      expect(
        result.update!.asset?.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-linux-x86_64-v1.1.0.tar.gz',
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

    test('falls back to MSI when Windows managed package is not installable',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'windows-x64': {
              'package_url':
                  'https://cdn.example.com/com.secondloop.secondloop-1.1.0-full.nupkg',
              'sha256': 'abc123',
            },
          },
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

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-win.msi');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test(
        'falls back to manual macOS installer when managed archive is not installable',
        () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: false);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        releaseModeOverride: true,
        macosManagedUpdateClient: macosClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        currentArchitectureOverride: 'arm64',
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'darwin-aarch64': {
              'archive_url':
                  'https://cdn.example.com/SecondLoop-macos-arm64-v1.1.0.app.tar.gz',
              'sha256': 'arm64sha',
            },
          },
          'assets': [
            {
              'name': 'SecondLoop-macos-v1.1.0.dmg',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-macos-v1.1.0.dmg');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-macos-v1.1.0.dmg',
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
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
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

    test(
        'falls back to MSI when Windows runtime is unavailable even with exact app id manifest package',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: false,
        appIdValue: 'com.secondloop.secondloopdev',
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'version': '1.1.0',
          'release_page_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'windows-x64': {
              'name': 'com.secondloop.secondloopdev-1.1.0-full.nupkg',
              'package_url':
                  'https://cdn.example.com/com.secondloop.secondloopdev-1.1.0-full.nupkg',
              'sha256': 'abc123',
              'app_id': 'com.secondloop.secondloopdev',
              'install_mode': 'velopack',
            },
          },
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

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop-win.msi');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-win.msi',
      );
    });

    test('records missing integrity metadata as manual fallback reason',
        () async {
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
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
            },
          },
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

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        logger.records.any((entry) =>
            entry.type == UpdateEventType.manualFallback &&
            entry.message == 'windows_integrity_missing'),
        isTrue,
      );
    });
  });
}
