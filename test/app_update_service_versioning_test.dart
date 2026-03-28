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

    test('checkForUpdates rejects release tags outside x.y.z', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'tag_name': 'v1.0.0.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.0.0.1',
          'assets': <Object?>[],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNull);
      expect(result.errorMessage, 'unsupported_version_format');
    });

    test('sameNormalizedVersion rejects non-strict prerelease values', () {
      expect(sameNormalizedVersion('1.1.0-beta', '1.1.0'), isFalse);
      expect(sameNormalizedVersion('1.1.0', '1.1.0-beta'), isFalse);
    });

    test('checkForUpdates rejects current versions outside x.y.z', () async {
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

      expect(result.update, isNull);
      expect(result.errorMessage, 'unsupported_version_format');
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
