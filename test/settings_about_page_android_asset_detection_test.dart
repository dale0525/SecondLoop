import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/about_page.dart';

import 'test_i18n.dart';

const _fakeAndroidApkSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class _FakeAboutUpdateService extends AppUpdateService {
  _FakeAboutUpdateService({required this.result});

  AppUpdateCheckResult result;

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async => result;
}

class _FakeAndroidApkDownloader implements AndroidApkDownloader {
  int downloadCalls = 0;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    downloadCalls += 1;
    onProgress(
      const AndroidApkDownloadProgress(receivedBytes: 1, totalBytes: 2),
    );
    return File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
  }
}

class _FakeAndroidApkInstaller implements AndroidApkInstaller {
  @override
  Future<void> installApk({required String apkPath}) async {}
}

void main() {
  testWidgets(
      'About page offers Android in-app update when asset URL is apk but name has no suffix',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    try {
      final downloader = _FakeAndroidApkDownloader();
      final installer = _FakeAndroidApkInstaller();
      final update = AppUpdateAvailability(
        currentVersion: '1.0.1+99',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.externalDownload,
        asset: AppUpdateAsset(
          name: 'download',
          downloadUri: Uri.parse(
            'https://cdn.example.com/SecondLoop-android-arm64-v8a.apk?token=1',
          ),
          sha256: _fakeAndroidApkSha256,
        ),
      );
      final service = _FakeAboutUpdateService(
        result:
            AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AboutPage(
              updateService: service,
              runtimeVersionLoader: () async => const AppRuntimeVersion(
                version: '1.0.1',
                buildNumber: '99',
              ),
              androidApkDownloader: downloader,
              androidApkInstaller: installer,
              enableAndroidApkInstallInDebug: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('about_check_updates')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('about_auto_update')));
      await tester.pump();

      expect(downloader.downloadCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'About page does not offer Android in-app update when apk asset lacks sha256',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    try {
      final downloader = _FakeAndroidApkDownloader();
      final installer = _FakeAndroidApkInstaller();
      final update = AppUpdateAvailability(
        currentVersion: '1.0.1+99',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.externalDownload,
        asset: AppUpdateAsset(
          name: 'download',
          downloadUri: Uri.parse(
            'https://cdn.example.com/SecondLoop-android-arm64-v8a.apk?token=1',
          ),
        ),
      );
      final service = _FakeAboutUpdateService(
        result:
            AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AboutPage(
              updateService: service,
              runtimeVersionLoader: () async => const AppRuntimeVersion(
                version: '1.0.1',
                buildNumber: '99',
              ),
              androidApkDownloader: downloader,
              androidApkInstaller: installer,
              enableAndroidApkInstallInDebug: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('about_check_updates')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
      expect(find.byKey(const ValueKey('about_manual_update')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'About page offers Android in-app update for apk asset even when install mode is seamless',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    try {
      final downloader = _FakeAndroidApkDownloader();
      final installer = _FakeAndroidApkInstaller();
      final update = AppUpdateAvailability(
        currentVersion: '1.0.1+99',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'download',
          downloadUri: Uri.parse(
            'https://cdn.example.com/SecondLoop-android-arm64-v8a.apk?token=1',
          ),
          sha256: _fakeAndroidApkSha256,
        ),
      );
      final service = _FakeAboutUpdateService(
        result:
            AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AboutPage(
              updateService: service,
              runtimeVersionLoader: () async => const AppRuntimeVersion(
                version: '1.0.1',
                buildNumber: '99',
              ),
              androidApkDownloader: downloader,
              androidApkInstaller: installer,
              enableAndroidApkInstallInDebug: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('about_check_updates')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('about_auto_update')));
      await tester.pump();

      expect(downloader.downloadCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}
