import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  group('AppUpdateService Android asset selection', () {
    test('matches canonical arm64 manifest when device reports alias abi',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['arm64'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-arm64-v8a': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/arm64.apk',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset, isNotNull);
      expect(result.update!.asset!.downloadUri.toString(),
          'https://cdn.example.com/arm64.apk');
    });

    test('does not fall back to arm64 manifest for x86_64 devices', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['x86_64'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-arm64-v8a': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/arm64.apk',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test('does not offer universal manifest to unsupported x86_64 devices',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['x86_64'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-universal': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/universal.apk',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test(
        'falls back to manual update when only abi-specific apk exists and supported abis are unknown',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const <String>[],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-arm64-v8a.apk',
              'browser_download_url': 'https://cdn.example.com/arm64.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.asset, isNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(
        result.update!.releasePageUri.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    });

    test(
        'does not offer manual Android fallback when only unsupported x86 assets exist and supported abis are unknown',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const <String>[],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-x86-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/x86.apk',
            },
            {
              'name': 'SecondLoop-android-x86_64-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/x86_64.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test(
        'does not offer manual Android fallback when manifest only exposes unsupported x86 assets and supported abis are unknown',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const <String>[],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-x86': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/x86.apk',
            },
            'android-x86_64': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/x86_64.apk',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test('keeps universal apk fallback when supported abis are unknown',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const <String>[],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/universal.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.name, 'SecondLoop-android-v1.1.0.apk');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/universal.apk',
      );
    });

    test('does not offer universal apk fallback to unsupported x86 devices',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['x86'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/universal.apk',
              'sha256': 'abc123',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test('does not offer universal apk fallback to unknown non-arm devices',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['riscv64'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/universal.apk',
              'sha256': 'abc123',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test('rejects Android updates when release tag is not strict semver',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const <String>[],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0-arm64-hotfix',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0-arm64-hotfix',
          'assets': [
            {
              'name': 'SecondLoop-android-v1.1.0-arm64-hotfix.apk',
              'browser_download_url':
                  'https://cdn.example.com/universal-hotfix.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, 'invalid_release_tag');
    });

    test('treats apk without sha256 as external download only', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['arm64-v8a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-arm64-v8a.apk',
              'browser_download_url': 'https://cdn.example.com/arm64.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.canUseAndroidApkInstaller, isFalse);
      expect(result.update!.downloadUri.toString(),
          'https://cdn.example.com/arm64.apk');
    });

    test('allows in-app Android install only when apk sha256 is present',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['arm64-v8a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-arm64-v8a.apk',
              'browser_download_url': 'https://cdn.example.com/arm64.apk',
              'sha256': 'abc123',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.canUseAndroidApkInstaller, isTrue);
    });

    test('does not treat unsupported x86 apk asset as universal fallback',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['arm64-v8a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-x86-v1.1.0.apk',
              'browser_download_url': 'https://cdn.example.com/x86.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, contains('no_platform_asset_for_android'));
    });

    test(
        'allows in-app Android install for manifest apk entries even when name is omitted',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['arm64-v8a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-arm64-v8a': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/download?id=arm64',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.canUseAndroidApkInstaller, isTrue);
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/download?id=arm64',
      );
    });
  });
}
