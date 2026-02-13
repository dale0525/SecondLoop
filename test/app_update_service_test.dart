import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';

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
              'name': 'SecondLoop-windows-x64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/win.msi',
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
      expect(update.downloadUri.toString(), 'https://cdn.example.com/win.msi');
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
              'name': 'SecondLoop-windows-x64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/win.msi',
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
  });
}
