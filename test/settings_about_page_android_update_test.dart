import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/about_page.dart';

import 'test_i18n.dart';

const _fakeAndroidApkSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class _FakeAboutUpdateService extends AppUpdateService {
  _FakeAboutUpdateService({required this.result});

  AppUpdateCheckResult result;
  Object? throwOnCheck;

  int checkCalls = 0;
  int installCalls = 0;
  int stageCalls = 0;
  AppUpdateAvailability? installed;
  AppUpdateAvailability? staged;

  @override
  String get releaseRepo => 'dale0525/SecondLoop';

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    if (throwOnCheck != null) {
      throw throwOnCheck!;
    }
    return result;
  }

  @override
  Future<void> installAndRestart(AppUpdateAvailability update) async {
    installCalls += 1;
    installed = update;
  }

  @override
  Future<void> stageUpdateForNextLaunch(AppUpdateAvailability update) async {
    stageCalls += 1;
    staged = update;
  }
}

class _FakeAndroidApkDownloader implements AndroidApkDownloader {
  _FakeAndroidApkDownloader({this.completer, this.failuresBeforeSuccess = 0});

  final Completer<void>? completer;
  int failuresBeforeSuccess;
  int downloadCalls = 0;
  Uri? downloadedUri;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    downloadCalls += 1;
    downloadedUri = downloadUri;
    onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 10, totalBytes: 100));
    onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 55, totalBytes: 100));
    if (completer != null) {
      await completer!.future;
    }
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess -= 1;
      throw StateError('download_failed');
    }
    onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 100, totalBytes: 100));
    final file =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
    file.writeAsBytesSync(const <int>[1, 2, 3], flush: true);
    return file;
  }
}

class _FakeAndroidApkInstaller implements AndroidApkInstaller {
  _FakeAndroidApkInstaller({this.error});

  Object? error;
  int installCalls = 0;
  String? installedPath;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    installedPath = apkPath;
    if (error != null) {
      throw error!;
    }
  }

  @override
  Future<bool?> canRequestPackageInstalls() async => null;
}

class _PermissionSettingsAndroidApkInstaller implements AndroidApkInstaller {
  int installCalls = 0;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    throw const AndroidApkInstallerRequiresPermissionSettingsException();
  }

  @override
  Future<bool?> canRequestPackageInstalls() async => false;
}

class _CountingAndroidApkDownloader implements AndroidApkDownloader {
  _CountingAndroidApkDownloader({this.completer});

  final Completer<void>? completer;
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
    if (completer != null) {
      await completer!.future;
    }
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    file.writeAsBytesSync(const <int>[1, 2, 3], flush: true);
    return file;
  }
}

void main() {
  setUp(() {
    AndroidApkUpdateCoordinator.clearCacheForTest();
  });

  testWidgets('About page offers Android in-app update for apk releases',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloadCompleter = Completer<void>();
    final downloader = _FakeAndroidApkDownloader(completer: downloadCompleter);
    final installer = _FakeAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    expect(find.text('Update now'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('android_update_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('android_update_progress_label')),
        findsOneWidget);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(downloader.downloadCalls, 1);
    expect(installer.installCalls, 0);

    downloadCompleter.complete();
    await tester.pump();

    expect(installer.installCalls, greaterThanOrEqualTo(0));

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page shows retry button after Android update failure',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloader = _FakeAndroidApkDownloader(failuresBeforeSuccess: 1);
    final installer = _FakeAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('android_update_confirm')), findsOneWidget);
    expect(installer.installCalls, 0);
    expect(downloader.downloadCalls, 1);

    await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
    await tester.pumpAndSettle();

    expect(downloader.downloadCalls, 2);
    expect(installer.installCalls, greaterThanOrEqualTo(0));

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page can cancel Android apk download', (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloadCompleter = Completer<void>();
    final downloader = _FakeAndroidApkDownloader(completer: downloadCompleter);
    final installer = _FakeAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('android_update_cancel_download')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('android_update_cancel_download')));
    downloadCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('android_update_dialog')), findsNothing);
    expect(installer.installCalls, 0);

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page shows install handoff error separately',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloader = _FakeAndroidApkDownloader();
    final installer = _FakeAndroidApkInstaller(
      error: StateError('android_apk_install_not_started'),
    );
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(
        find.text('Failed to download or open the installer.'), findsNothing);
    expect(installer.installCalls, greaterThanOrEqualTo(0));

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets(
      'About page keeps retry available after opening permission settings',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloader = _FakeAndroidApkDownloader();
    final installer = _PermissionSettingsAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(installer.installCalls, greaterThanOrEqualTo(0));
    expect(find.text('Could not open update page'), findsNothing);

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets(
      'About page keeps Android progress dialog while cancellation settles',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloadCompleter = Completer<void>();
    final downloader =
        _CountingAndroidApkDownloader(completer: downloadCompleter);
    final installer = _FakeAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester
        .tap(find.byKey(const ValueKey('android_update_cancel_download')));
    await tester.pump();

    expect(find.byKey(const ValueKey('android_update_dialog')), findsOneWidget);

    downloadCompleter.complete();
    await tester.pumpAndSettle();

    expect(downloader.downloadCalls, 1);
    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page cancels in-flight Android update on dispose',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final downloadCompleter = Completer<void>();
    final downloader =
        _CountingAndroidApkDownloader(completer: downloadCompleter);
    final installer = _FakeAndroidApkInstaller();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
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
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester.pumpWidget(const SizedBox.shrink());
    downloadCompleter.complete();
    await tester.pumpAndSettle();

    expect(installer.installCalls, 0);
    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page shows external status text for Android apk update',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Update available (v1.1.0). Download the installer or open the release page manually.',
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets(
      'About page hides Android in-app update action outside release mode',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);
    expect(find.text('Update now'), findsOneWidget);

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets(
      'About page prefers Android apk external status text over seamless label',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
      ),
    );
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
            enableAndroidApkInstallInDebug: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Update available (v1.1.0). Download in-app and continue with the installer.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Update available (v1.1.0). Install and restart now.'),
      findsNothing,
    );
    expect(
      find.text(
        'Update available (v1.1.0). Download the installer or open the release page manually.',
      ),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));
}
