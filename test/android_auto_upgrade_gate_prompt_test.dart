import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

import 'support/android_auto_upgrade_gate_test_support.dart';
import 'test_i18n.dart';

AppUpdateAvailability _androidApkUpdate({String latestTag = 'v1.1.0'}) {
  return AppUpdateAvailability(
    currentVersion: '1.0.0+1',
    latestTag: latestTag,
    releasePageUri: Uri.parse(
      'https://github.com/dale0525/SecondLoop/releases/tag/$latestTag',
    ),
    installMode: AppUpdateInstallMode.externalDownload,
    asset: AppUpdateAsset(
      name: 'SecondLoop-android-arm64-v8a.apk',
      downloadUri: Uri.parse('https://cdn.example.com/secondloop.apk'),
      sha256: fakeAndroidApkSha256,
    ),
  );
}

AppUpdateAvailability _externalUpdate({String latestTag = 'v1.1.0'}) {
  return AppUpdateAvailability(
    currentVersion: '1.0.0+1',
    latestTag: latestTag,
    releasePageUri: Uri.parse(
      'https://github.com/dale0525/SecondLoop/releases/tag/$latestTag',
    ),
    installMode: AppUpdateInstallMode.externalDownload,
  );
}

Future<void> _pumpAndroidGate(
  WidgetTester tester, {
  required AndroidAutoUpdateService service,
  AndroidApkUpdateCoordinator? coordinator,
}) {
  return tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: AutoUpgradeGate(
          updateService: service,
          releaseNotesService: FakeReleaseNotesService(
            result: const ReleaseNotesFetchResult(),
          ),
          androidApkUpdateCoordinator: coordinator,
          androidApkDownloader: NoopAndroidApkDownloader(),
          androidApkInstaller: NoopAndroidApkInstaller(),
          enableInDebug: true,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    ),
  );
}

Future<void> _resumeApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _runAsAndroid(Future<void> Function() body) async {
  final oldPlatform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = oldPlatform;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AndroidApkUpdateCoordinator.clearCacheForTest();
  });

  testWidgets('Android apk prompt explains in-app install flow',
      (tester) async {
    await _runAsAndroid(() async {
      final service = AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: _androidApkUpdate(),
        ),
      );

      await _pumpAndroidGate(tester, service: service);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('update_prompt_ignore')), findsOneWidget);
      expect(find.byKey(const ValueKey('android_update_cancel')), findsNothing);
      expect(
        find.text('A newer Android version is available. '
            'You can download and install it now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Open the update page'), findsNothing);
    });
  });

  testWidgets(
      'clears pending Android install permission when same tag stops being apk candidate',
      (tester) async {
    await _runAsAndroid(() async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        AutoUpgradeGate.updateNoticeLastTagPrefsKey: 'v1.1.0',
        AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey: nowMs,
      });
      final coordinator = FakeAndroidApkUpdateCoordinator(
        error: const AndroidApkInstallerRequiresPermissionSettingsException(),
        canRequestPackageInstallsResult: false,
      );
      final service = AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: _androidApkUpdate(),
        ),
      );

      await _pumpAndroidGate(
        tester,
        service: service,
        coordinator: coordinator,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
      await settleAndroidUpdateFlow(tester);
      expect(coordinator.performCalls, 1);

      await tester.tap(find.byKey(const ValueKey('android_update_cancel')));
      await tester.pumpAndSettle();

      service.result = AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: _externalUpdate(),
      );
      await _resumeApp(tester);
      expect(find.byType(AlertDialog), findsNothing);

      coordinator.error = null;
      coordinator.canRequestPackageInstallsResult = true;
      service.result = AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: _androidApkUpdate(),
      );
      await _resumeApp(tester);

      expect(coordinator.performCalls, 1);
      expect(
          find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
    });
  });

  testWidgets('Android apk ignore only suppresses the same tag in-session',
      (tester) async {
    await _runAsAndroid(() async {
      final service = AndroidAutoUpdateService(
        result: AppUpdateCheckResult(
          currentVersion: '1.0.0+1',
          update: _androidApkUpdate(),
        ),
      );

      await _pumpAndroidGate(tester, service: service);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('update_prompt_ignore')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update_prompt_dialog')), findsNothing);

      service.result = AppUpdateCheckResult(
        currentVersion: '1.0.0+1',
        update: _androidApkUpdate(latestTag: 'v1.2.0'),
      );
      await _resumeApp(tester);

      expect(service.checkCalls, 2);
      expect(
          find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
      expect(find.text('Update available: v1.2.0'), findsOneWidget);
    });
  });
}
