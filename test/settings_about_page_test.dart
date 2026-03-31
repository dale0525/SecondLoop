import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/about_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

class _FakeAboutUpdateService extends AppUpdateService {
  _FakeAboutUpdateService({required this.result});

  final AppUpdateCheckResult result;
  Object? throwOnCheck;

  int checkCalls = 0;
  int installCalls = 0;
  int stageCalls = 0;
  AppUpdateAvailability? installed;
  AppUpdateAvailability? staged;

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
    return File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
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
}

class _PermissionSettingsAndroidApkInstaller implements AndroidApkInstaller {
  int installCalls = 0;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    throw const AndroidApkInstallerRequiresPermissionSettingsException();
  }
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
    await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
    return file;
  }
}

void main() {
  testWidgets('Settings support section includes About entry', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aboutEntry = find.byKey(const ValueKey('settings_about'));
    await tester.dragUntilVisible(
      aboutEntry,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(aboutEntry, findsOneWidget);

    await tester.tap(aboutEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('About page shows version and update actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
        downloadUri: Uri.parse('https://cdn.example.com/linux.tar.gz'),
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
            externalUriLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_open_homepage')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_manual_update')), findsOneWidget);
    expect(find.textContaining('1.0.1+99'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.textContaining('v1.1.0'), findsWidgets);
    expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');

    await tester.tap(find.byKey(const ValueKey('about_manual_update')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), update.releasePageUri.toString());

    await tester.tap(find.byKey(const ValueKey('about_open_homepage')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://secondloop.app');
  });

  testWidgets('About page manual update prefers Android apk download uri',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
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
            externalUriLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_manual_update')));
    await tester.pumpAndSettle();

    expect(opened.single.toString(),
        'https://cdn.example.com/SecondLoop-android.apk');
    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

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

    expect(find.byKey(const ValueKey('about_android_progress_bar')),
        findsOneWidget);
    expect(find.textContaining('55%'), findsOneWidget);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(downloader.downloadCalls, 1);
    expect(installer.installCalls, 0);

    downloadCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(installer.installCalls, 1);
    expect(installer.installedPath, isNotNull);

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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('about_android_retry')), findsOneWidget);
    expect(installer.installCalls, 0);
    expect(downloader.downloadCalls, 1);

    await tester.tap(find.byKey(const ValueKey('about_android_retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(downloader.downloadCalls, 2);
    expect(installer.installCalls, 1);

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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();

    expect(find.byKey(const ValueKey('about_android_cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_android_cancel')));
    downloadCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.byKey(const ValueKey('about_android_progress_bar')), findsNothing);
    expect(find.byKey(const ValueKey('about_android_retry')), findsNothing);
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.text('Failed to download or open the installer.'), findsNothing);
    expect(find.byKey(const ValueKey('about_android_retry')), findsOneWidget);
    expect(installer.installCalls, 1);

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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(installer.installCalls, 1);
    expect(find.byKey(const ValueKey('about_android_retry')), findsOneWidget);
    expect(find.text('Could not open update page'), findsNothing);

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page stages update for next launch', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.stagedNextLaunch,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
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
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.installCalls, 0);
    expect(service.stageCalls, 1);
    expect(service.staged?.latestTag, 'v1.1.0');
  });

  testWidgets(
      'About page shows managed update action on Windows when available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/SecondLoop-win.nupkg'),
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

    expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.installCalls, 1);
    expect(service.stageCalls, 0);
    expect(service.installed?.latestTag, 'v1.1.0');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'About page keeps manual update only on Windows external download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-win.msi',
        downloadUri: Uri.parse('https://cdn.example.com/SecondLoop-win.msi'),
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
            externalUriLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('about_manual_update')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(
      opened.single.toString(),
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
    );
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'About page keeps update action disabled while cancellation settles',
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.byKey(const ValueKey('about_android_cancel')));
    await tester.pump();

    final autoUpdateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('about_auto_update')),
    );
    expect(autoUpdateButton.onPressed, isNull);

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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
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

  testWidgets('About page clears stale update result after check failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: AppUpdateAvailability(
          currentVersion: '1.0.1+99',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.stagedNextLaunch,
          asset: AppUpdateAsset(
            name: 'pkg.nupkg',
            downloadUri: Uri.parse('https://cdn.example.com/pkg.nupkg'),
          ),
        ),
      ),
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
    expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

    service.throwOnCheck = StateError('network_down');
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
  });
}
