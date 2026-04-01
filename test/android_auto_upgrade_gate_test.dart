import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'dart:io';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

import 'test_i18n.dart';

const _fakeAndroidApkSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class _AndroidAutoUpdateService extends AppUpdateService {
  _AndroidAutoUpdateService({required this.result});

  final AppUpdateCheckResult result;

  int applyPendingCalls = 0;
  int checkCalls = 0;

  @override
  Future<bool> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    return false;
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    return result;
  }
}

class _FakeReleaseNotesService extends ReleaseNotesService {
  _FakeReleaseNotesService({required this.result});

  final ReleaseNotesFetchResult result;
  int fetchCalls = 0;

  @override
  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    fetchCalls += 1;
    return result;
  }
}

class _ThrowingReleaseNotesService extends ReleaseNotesService {
  _ThrowingReleaseNotesService({required this.error});

  final Object error;
  int fetchCalls = 0;

  @override
  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    fetchCalls += 1;
    throw error;
  }
}

class _NoopAndroidApkDownloader implements AndroidApkDownloader {
  _NoopAndroidApkDownloader({this.completer});

  final Completer<void>? completer;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 50, totalBytes: 100));
    if (completer != null) {
      await completer!.future;
    }
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
    final file =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
    file.writeAsBytesSync(const <int>[1, 2, 3], flush: true);
    return file;
  }
}

class _NoopAndroidApkInstaller implements AndroidApkInstaller {
  @override
  Future<void> installApk({required String apkPath}) async {}
}

class _FakeAndroidApkUpdateCoordinator extends AndroidApkUpdateCoordinator {
  _FakeAndroidApkUpdateCoordinator({
    this.error,
    this.reuseVerifiedDownloads = false,
  }) : super(
          downloader: _NoopAndroidApkDownloader(),
          installer: _NoopAndroidApkInstaller(),
        );

  Object? error;
  final bool reuseVerifiedDownloads;

  int performCalls = 0;
  int downloadCalls = 0;
  final Set<String> _verifiedSha256 = <String>{};

  @override
  Future<void> performUpdate({
    required AppUpdateAsset asset,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    performCalls += 1;
    final normalizedSha256 = asset.sha256?.trim().toLowerCase();
    final hasVerifiedCache = reuseVerifiedDownloads &&
        normalizedSha256 != null &&
        normalizedSha256.isNotEmpty &&
        _verifiedSha256.contains(normalizedSha256);
    if (!hasVerifiedCache) {
      downloadCalls += 1;
      onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 100, totalBytes: 100),
      );
      if (reuseVerifiedDownloads &&
          normalizedSha256 != null &&
          normalizedSha256.isNotEmpty) {
        _verifiedSha256.add(normalizedSha256);
      }
    } else {
      onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 1, totalBytes: 1),
      );
    }
    if (error != null) {
      throw error!;
    }
  }
}

Future<void> _settleAndroidUpdateFlow(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = null;
    AndroidApkUpdateCoordinator.clearCacheForTest();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows Android update dialog on launch and dismisses on cancel',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _AndroidAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: AppUpdateAvailability(
          currentVersion: '1.0.0+1',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
          installMode: AppUpdateInstallMode.externalDownload,
          asset: AppUpdateAsset(
            name: 'SecondLoop-android-arm64-v8a.apk',
            downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
            sha256: _fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService = _FakeReleaseNotesService(
      result: const ReleaseNotesFetchResult(
        notes: ReleaseNotes(
          version: 'v1.1.0',
          summary: 'Better Android updating.',
          highlights: ['Progress UI', 'Installer handoff'],
          sections: [],
        ),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader: _NoopAndroidApkDownloader(),
            androidApkInstaller: _NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCalls, 1);
    expect(releaseNotesService.fetchCalls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('v1.1.0'), findsOneWidget);

    await tester.tap(find.text('Cancel', skipOffstage: false));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('can cancel Android update download from dialog', (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final downloadCompleter = Completer<void>();
    final service = _AndroidAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: AppUpdateAvailability(
          currentVersion: '1.0.0+1',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
          installMode: AppUpdateInstallMode.externalDownload,
          asset: AppUpdateAsset(
            name: 'SecondLoop-android-arm64-v8a.apk',
            downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
            sha256: _fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService = _FakeReleaseNotesService(
      result: const ReleaseNotesFetchResult(
        notes: ReleaseNotes(
          version: 'v1.1.0',
          summary: 'Better Android updating.',
          highlights: ['Progress UI'],
          sections: [],
        ),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader:
                _NoopAndroidApkDownloader(completer: downloadCompleter),
            androidApkInstaller: _NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
    await tester.pump();

    expect(find.byKey(const ValueKey('android_update_cancel_download')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('android_update_cancel_download')));
    downloadCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('home'), findsOneWidget);

    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('does not reopen Android dialog after cancelling same version',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _AndroidAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: AppUpdateAvailability(
          currentVersion: '1.0.0+1',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
          installMode: AppUpdateInstallMode.externalDownload,
          asset: AppUpdateAsset(
            name: 'SecondLoop-android-arm64-v8a.apk',
            downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
            sha256: _fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService =
        _FakeReleaseNotesService(result: const ReleaseNotesFetchResult());

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader: _NoopAndroidApkDownloader(),
            androidApkInstaller: _NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCalls, 2);
    expect(find.byType(AlertDialog), findsNothing);

    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('checks again when app resumes on Android', (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _AndroidAutoUpdateService(
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );
    final releaseNotesService =
        _FakeReleaseNotesService(result: const ReleaseNotesFetchResult());

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader: _NoopAndroidApkDownloader(),
            androidApkInstaller: _NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(service.checkCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCalls, 2);
    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('shows install handoff error in Android dialog', (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = _FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.installLaunch,
          cause: 'android_apk_install_not_started',
        ),
      );
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkUpdateCoordinator: coordinator,
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('opens release page for manual update after Android dialog error',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = _FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.installLaunch,
          cause: 'android_apk_install_not_started',
        ),
      );
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );
      final opened = <Uri>[];

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkUpdateCoordinator: coordinator,
              externalUriLauncher: (uri) async {
                opened.add(uri);
                return true;
              },
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);
      await tester.tap(find.byKey(const ValueKey('android_update_manual')));
      await tester.pumpAndSettle();

      expect(
        opened.single.toString(),
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      );
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'does not show handoff error when installer opens permission settings',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = _FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
      );
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkUpdateCoordinator: coordinator,
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);

      expect(find.text('Could not open update page'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'shows Android dialog for apk update even when install mode is not external',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );
      final releaseNotesService = _FakeReleaseNotesService(
        result: const ReleaseNotesFetchResult(),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: releaseNotesService,
              androidApkDownloader: _NoopAndroidApkDownloader(),
              androidApkInstaller: _NoopAndroidApkInstaller(),
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(releaseNotesService.fetchCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'rechecks Android update dialog after resuming from permission settings',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = _FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
      );
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkUpdateCoordinator: coordinator,
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'reuses verified Android apk after resuming from permission settings',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = _FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        reuseVerifiedDownloads: true,
      );
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                result: const ReleaseNotesFetchResult(),
              ),
              androidApkUpdateCoordinator: coordinator,
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);
      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 1);

      await tester.tap(find.text('Cancel', skipOffstage: false));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('android_update_confirm')));
      await _settleAndroidUpdateFlow(tester);

      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 2);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('shows Android dialog even when release notes fetch throws',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );
      final releaseNotesService = _ThrowingReleaseNotesService(
          error: StateError('release_notes_failed'));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: releaseNotesService,
              androidApkDownloader: _NoopAndroidApkDownloader(),
              androidApkInstaller: _NoopAndroidApkInstaller(),
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(releaseNotesService.fetchCalls, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'shows Android update dialog for apk asset even when install mode is seamless',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = _AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: AppUpdateAvailability(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
                'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-android-arm64-v8a.apk',
              downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
              sha256: _fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: _FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkDownloader: _NoopAndroidApkDownloader(),
              androidApkInstaller: _NoopAndroidApkInstaller(),
              enableInDebug: true,
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}
