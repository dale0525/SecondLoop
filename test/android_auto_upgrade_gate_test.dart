import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'dart:io';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

import 'test_i18n.dart';

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
    return File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
  }
}

class _NoopAndroidApkInstaller implements AndroidApkInstaller {
  @override
  Future<void> installApk({required String apkPath}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
