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

    test(
        'returns no update when only abi-specific apk exists and supported abis are unknown',
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

    test('matches x86 manifest when device reports x86 alias abi', () async {
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
          'platforms': {
            'android-x86': {
              'install_mode': 'apk',
              'archive_url': 'https://cdn.example.com/x86.apk',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset, isNotNull);
      expect(
        result.update!.asset!.downloadUri.toString(),
        'https://cdn.example.com/x86.apk',
      );
    });

    test('matches x86 apk asset when device reports x86 alias abi', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['i686'],
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

      expect(result.update, isNotNull);
      expect(result.update!.asset?.name, 'SecondLoop-android-x86-v1.1.0.apk');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/x86.apk',
      );
    });
  });
}
