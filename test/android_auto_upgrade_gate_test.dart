import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

import 'support/android_auto_upgrade_gate_test_support.dart';
import 'test_i18n.dart';

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
    final service = AndroidAutoUpdateService(
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
            sha256: fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService = FakeReleaseNotesService(
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
            androidApkDownloader: NoopAndroidApkDownloader(),
            androidApkInstaller: NoopAndroidApkInstaller(),
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
    expect(find.text('Update available: v1.1.0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update_prompt_ignore')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('re-prompts after cancelling Android update download',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final downloadCompleter = Completer<void>();
    final service = AndroidAutoUpdateService(
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
            sha256: fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService = FakeReleaseNotesService(
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
                NoopAndroidApkDownloader(completer: downloadCompleter),
            androidApkInstaller: NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await settleAndroidUpdateFlow(tester);

    expect(find.byKey(const ValueKey('android_update_cancel_download')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('android_update_cancel_download')));
    downloadCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('home'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCalls, 2);
    expect(find.byType(AlertDialog), findsOneWidget);

    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  testWidgets('does not reopen Android dialog after cancelling same version',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = AndroidAutoUpdateService(
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
            sha256: fakeAndroidApkSha256,
          ),
        ),
      ),
    );
    final releaseNotesService =
        FakeReleaseNotesService(result: const ReleaseNotesFetchResult());

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader: NoopAndroidApkDownloader(),
            androidApkInstaller: NoopAndroidApkInstaller(),
            enableInDebug: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update_prompt_ignore')));
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
    final service = AndroidAutoUpdateService(
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );
    final releaseNotesService =
        FakeReleaseNotesService(result: const ReleaseNotesFetchResult());

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            releaseNotesService: releaseNotesService,
            androidApkDownloader: NoopAndroidApkDownloader(),
            androidApkInstaller: NoopAndroidApkInstaller(),
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
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.installLaunch,
          cause: 'android_apk_install_not_started',
        ),
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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
      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Could not open update page'), findsOneWidget);
      expect(find.textContaining('Downloading update'), findsNothing);
      expect(find.textContaining('Preparing update'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('opens release page for manual update after Android dialog error',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.installLaunch,
          cause: 'android_apk_install_not_started',
        ),
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
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
              releaseNotesService: FakeReleaseNotesService(
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
      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      await tester.tap(find.byKey(const ValueKey('update_progress_manual')));
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
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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
      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);

      expect(find.text('Could not open update page'), findsNothing);
      expect(
        find.text(
          'Allow installs from this app in system settings, then try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('android_update_progress_label')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('update_progress_bar')), findsNothing);
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
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );
      final releaseNotesService = FakeReleaseNotesService(
        result: const ReleaseNotesFetchResult(),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: releaseNotesService,
              androidApkDownloader: NoopAndroidApkDownloader(),
              androidApkInstaller: NoopAndroidApkInstaller(),
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
      'does not reopen Android update dialog while install permission is still missing',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        canRequestPackageInstallsResult: false,
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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

      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsNothing);
      expect(coordinator.permissionCheckCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'does not retry Android apk update automatically while install permission is still missing',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        reuseVerifiedDownloads: true,
        canRequestPackageInstallsResult: false,
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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
      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 1);

      await tester.tap(find.text('Cancel', skipOffstage: false));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsNothing);
      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('retries Android update after install permission is granted',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        canRequestPackageInstallsResult: false,
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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

      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      coordinator.error = null;
      coordinator.canRequestPackageInstallsResult = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(coordinator.permissionCheckCalls, 1);
      expect(coordinator.performCalls, 2);
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'retries Android apk install automatically after install permission is granted',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        reuseVerifiedDownloads: true,
        canRequestPackageInstallsResult: false,
      );
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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
      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);

      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 1);

      coordinator.error = null;
      coordinator.canRequestPackageInstallsResult = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(coordinator.permissionCheckCalls, 1);
      expect(coordinator.downloadCalls, 1);
      expect(coordinator.performCalls, 2);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
      'does not reopen Android dialog after installer handoff for same version',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final coordinator = FakeAndroidApkUpdateCoordinator();
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
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
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      expect(find.byType(AlertDialog), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(service.checkCalls, 2);
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('shows Android dialog even when release notes fetch throws',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );
      final releaseNotesService = ThrowingReleaseNotesService(
          error: StateError('release_notes_failed'));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: releaseNotesService,
              androidApkDownloader: NoopAndroidApkDownloader(),
              androidApkInstaller: NoopAndroidApkInstaller(),
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
      final service = AndroidAutoUpdateService(
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
              sha256: fakeAndroidApkSha256,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              releaseNotesService: FakeReleaseNotesService(
                  result: const ReleaseNotesFetchResult()),
              androidApkDownloader: NoopAndroidApkDownloader(),
              androidApkInstaller: NoopAndroidApkInstaller(),
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
