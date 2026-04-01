import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/app_update_service.dart';

import '../tools/generate_update_manifest_lib.dart';

void main() {
  group('Android ABI alias compatibility', () {
    test('matches armv7 asset aliases for armeabi-v7a devices', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['armeabi-v7a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'assets': [
            {
              'name': 'SecondLoop-android-armv7.apk',
              'browser_download_url': 'https://cdn.example.com/armv7.apk',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.name, 'SecondLoop-android-armv7.apk');
      expect(result.update!.downloadUri.toString(),
          'https://cdn.example.com/armv7.apk');
    });

    test('matches armv7 manifest keys for armeabi-v7a devices', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.android,
        releaseModeOverride: true,
        androidSupportedAbisOverride: const ['armeabi-v7a'],
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '9'),
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.1.0',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          'platforms': {
            'android-armv7': {
              'archive_url': 'https://cdn.example.com/armv7.apk',
              'sha256': 'abc123',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.downloadUri.toString(),
          'https://cdn.example.com/armv7.apk');
    });

    test('resolves armv7 file names to armeabi-v7a manifest key', () {
      expect(
          resolveAndroidPlatformKeyForTest(
              'SecondLoop-android-armv7-v1.2.3.apk'),
          'android-armeabi-v7a');
      expect(
          resolveAndroidPlatformKeyForTest(
              'SecondLoop-android-arm-v7a-v1.2.3.apk'),
          'android-armeabi-v7a');
    });
  });
}
