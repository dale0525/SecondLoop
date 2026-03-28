import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_helpers.dart';
import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  group('AppUpdateService version constraints', () {
    test('checkForUpdates accepts uppercase V release tags', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'V1.0.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/V1.0.1',
          'assets': <Object?>[
            <String, Object?>{
              'name': 'SecondLoop-win.msi',
              'browser_download_url':
                  'https://cdn.example.com/SecondLoop-win.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.0.1');
    });

    test('checkForUpdates accepts release tags with fourth segment', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'v1.0.1.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.1.1',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.0.1.1');
    });

    test('checkForUpdates treats fourth segment as newer when base matches',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.1', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'v1.0.1.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.1.1',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.0.1.1');
    });

    test('sameNormalizedVersion accepts prerelease variants only', () {
      expect(sameNormalizedVersion('1.1.0-beta', '1.1.0'), isTrue);
      expect(sameNormalizedVersion('1.1.0', '1.1.0-beta'), isTrue);
      expect(sameNormalizedVersion('1.1.0.7', '1.1.0'), isFalse);
    });

    test('prerelease identifiers keep semantic ordering', () {
      expect(compareReleaseTagWithCurrentVersion('1.1.0-alpha', '1.1.0-beta'),
          lessThan(0));
      expect(compareReleaseTagWithCurrentVersion('1.1.0-beta', '1.1.0-rc.1'),
          lessThan(0));
      expect(compareReleaseTagWithCurrentVersion('1.1.0-rc.2', '1.1.0-rc.1'),
          greaterThan(0));
      expect(
          compareReleaseTagWithCurrentVersion('1.1.0-beta', '1.1.0-beta'), 0);
    });

    test(
        'sameNormalizedVersion does not treat prerelease build counters as equal',
        () {
      expect(sameNormalizedVersion('1.1.0-rc.1', '1.1.0'), isFalse);
      expect(sameNormalizedVersion('1.1.0', '1.1.0-rc.1'), isFalse);
    });

    test('checkForUpdates rejects non-version release tags', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'release-2026-03-28',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/release-2026-03-28',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, 'unsupported_version_format');
    });

    test('checkForUpdates treats final release as newer than prerelease',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async => const AppRuntimeVersion(
          version: '1.1.0-rc.1',
          buildNumber: '1',
        ),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.1.0');
    });

    test('checkForUpdates accepts current versions outside strict x.y.z',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0.1', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'v1.0.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.1',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.errorMessage, isNull);
      expect(result.update, isNotNull);
      expect(result.update!.latestTag, 'v1.0.1');
    });

    test('checkForUpdates keeps base path for custom release origins',
        () async {
      late Uri requestedUri;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        releaseRepoOverride: '',
        releaseApiOriginOverride: 'https://updates.example.com/custom/base/',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (uri) async {
          requestedUri = uri;
          return <String, Object?>{
            'tag_name': 'v1.0.1',
            'html_url':
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.1',
            'assets': <Object?>[],
          };
        },
      );

      await service.checkForUpdates();

      expect(
        requestedUri.toString(),
        'https://updates.example.com/custom/base/api/releases/latest',
      );
    });
  });
}
