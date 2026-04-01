import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_helpers.dart';
import 'package:secondloop/core/update/app_update_resolution.dart';
import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  group('AppUpdateService version constraints', () {
    test('Windows MSI identity matcher distinguishes prod and dev installers',
        () {
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop-win.msi',
          appId: 'com.secondloop.secondloop',
        ),
        isTrue,
      );
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop Dev-win.msi',
          appId: 'com.secondloop.secondloop',
        ),
        isFalse,
      );
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop Dev-win.msi',
          appId: 'com.secondloop.secondloopdev',
        ),
        isTrue,
      );
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop-win.msi',
          appId: 'com.secondloop.secondloopdev',
        ),
        isFalse,
      );
    });

    test('Windows MSI identity matcher falls back to generic matcher rules',
        () {
      expect(isWindowsMsiInstallerName('SecondLoop-win.msi'), isTrue);
      expect(isWindowsMsiInstallerName('SecondLoop Dev-win.msi'), isTrue);
      expect(isWindowsMsiInstallerName('AnotherApp-win.msi'), isFalse);
    });

    test('Windows MSI identity matcher avoids broad dev substring matches', () {
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop-device-win.msi',
          appId: 'com.secondloop.secondloopdev',
        ),
        isFalse,
      );
      expect(
        isWindowsMsiInstallerNameForApp(
          'SecondLoop-devtools-win.msi',
          appId: 'com.secondloop.secondloopdev',
        ),
        isFalse,
      );
    });

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

    test('checkForUpdates rejects release tags with fourth segment', () async {
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

      expect(result.update, isNull);
      expect(result.errorMessage, 'unsupported_version_format');
    });

    test('sameNormalizedVersion only matches strict x.y.z versions', () {
      expect(sameNormalizedVersion('1.1.0', '1.1.0'), isTrue);
      expect(sameNormalizedVersion('v1.1.0', '1.1.0+7'), isTrue);
      expect(sameNormalizedVersion('1.1.0-beta', '1.1.0'), isFalse);
      expect(sameNormalizedVersion('1.1.0.7', '1.1.0'), isFalse);
    });

    test('parseComparableAppVersion only accepts strict x.y.z values', () {
      expect(parseComparableAppVersion('v1.2.3'), isNotNull);
      expect(parseComparableAppVersion('1.2.3+4'), isNotNull);
      expect(parseComparableAppVersion('1.2.3.4'), isNull);
      expect(parseComparableAppVersion('1.2.3-rc.1'), isNull);
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

    test('checkForUpdates rejects current versions outside strict x.y.z',
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

    test(
        'parseUpdateUri rejects unsupported schemes, http, and bare windows paths',
        () {
      expect(parseUpdateUri('javascript:alert(1)'), isNull);
      expect(parseUpdateUri('http://updates.example.com/releases/latest.json'),
          isNull);
      expect(parseUpdateUri('C:/temp/update.nupkg'), isNull);
      expect(
        parseUpdateUri('https://updates.example.com/releases/latest.json'),
        isNotNull,
      );
    });

    test('parseUpdateUri allows non-https schemes only when explicitly enabled',
        () {
      expect(
        parseUpdateUri(
          'http://updates.example.com/releases/latest.json',
          allowHttp: true,
        )?.scheme,
        'http',
      );
      expect(
        parseUpdateUri(
          'file:///C:/temp/update.nupkg',
          allowFile: true,
        )?.scheme,
        'file',
      );
    });

    test(
        'checkForUpdates keeps base path for custom release origins without trailing slash',
        () async {
      late Uri requestedUri;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        releaseRepoOverride: '',
        releaseApiOriginOverride: 'https://updates.example.com/custom/base',
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

    test(
        'fallbackReleasePageUri uses configured origin root for self-hosted feeds',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        releaseRepoOverride: '',
        releaseApiOriginOverride: 'https://updates.example.com/custom/base/',
      );

      expect(
        service.fallbackReleasePageUri.toString(),
        'https://updates.example.com/custom/base/',
      );
    });
  });
}
