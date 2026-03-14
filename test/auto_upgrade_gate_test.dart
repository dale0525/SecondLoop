import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/core/update/update_restart_activity.dart';
import 'test_i18n.dart';

class _FakeAutoUpdateService extends AppUpdateService {
  _FakeAutoUpdateService({
    required this.result,
    this.throwOnApplyPending = false,
    this.releaseRepoValue = 'dale0525/SecondLoop',
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;
  final String releaseRepoValue;

  int checkCalls = 0;
  int installCalls = 0;
  int stageCalls = 0;
  int applyStagedRestartCalls = 0;
  int applyPendingCalls = 0;
  AppUpdateAvailability? installed;
  AppUpdateAvailability? staged;

  @override
  String get releaseRepo => releaseRepoValue;

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
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

  @override
  Future<void> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    if (throwOnApplyPending) {
      throw StateError('apply_pending_failed');
    }
  }

  @override
  Future<void> applyStagedUpdateAndRestart() async {
    applyStagedRestartCalls += 1;
  }
}

void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    required _FakeAutoUpdateService service,
    AutoUpgradeGateExternalUriLauncher? externalUriLauncher,
  }) {
    return tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            enableInDebug: true,
            externalUriLauncher: externalUriLauncher,
            child: const Scaffold(
              body: Text('home'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('linux seamless update stays passive until user confirms',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
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
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.checkCalls, 1);
    expect(service.applyPendingCalls, 1);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(UpdateBadgePrefs.value.value, 'v1.1.0');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Settings > About'), findsOneWidget);
    expect(find.textContaining('manual download'), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('skips install when only external download is available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(service.applyPendingCalls, 1);
  });

  testWidgets('windows seamless update shows passive reminder and badge only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
      ),
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 1);
    expect(service.applyPendingCalls, 1);
    expect(UpdateBadgePrefs.value.value, 'v1.1.0');
    expect(find.byType(SnackBar), findsOneWidget);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets('windows external update shows manual reminder and badge state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.2.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-win.msi',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-win-v1.2.0.msi'),
      ),
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(service.applyPendingCalls, 1);
    expect(UpdateBadgePrefs.value.value, 'v1.2.0');
    expect(find.byType(SnackBar), findsOneWidget);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets('windows update never requests staged restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
    UpdateRestartActivity.resetForTests();
    addTearDown(UpdateRestartActivity.resetForTests);

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.3.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.3.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-win.msi',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-win-v1.3.0.msi'),
      ),
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.stageCalls, 0);
    expect(service.applyStagedRestartCalls, 0);
    expect(service.applyPendingCalls, 1);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets('shows manual fallback notice when pending apply fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      throwOnApplyPending: true,
      releaseRepoValue: 'acme/SecondLoopFork',
      result: const AppUpdateCheckResult(currentVersion: '1.0.1+99'),
    );
    Uri? openedUri;

    await pumpGate(
      tester,
      service: service,
      externalUriLauncher: (uri) async {
        openedUri = uri;
        return true;
      },
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Auto update failed'), findsOneWidget);
    expect(find.text('Manual update'), findsOneWidget);

    await tester.tap(find.text('Manual update'));
    await tester.pumpAndSettle();

    expect(openedUri,
        Uri.parse('https://github.com/acme/SecondLoopFork/releases/latest'));
    expect(service.checkCalls, 1);
  });

  testWidgets('skips pending apply and still checks for updates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      throwOnApplyPending: true,
      result: const AppUpdateCheckResult(currentVersion: '1.0.1+99'),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 1);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('macOS seamless update stays passive until user confirms',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.2.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-macos-v1.2.0.app.tar.gz',
        downloadUri: Uri.parse(
          'https://cdn.example.com/SecondLoop-macos-v1.2.0.app.tar.gz',
        ),
      ),
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(service.applyPendingCalls, 1);
    expect(UpdateBadgePrefs.value.value, 'v1.2.0');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Settings > About'), findsOneWidget);
    expect(find.textContaining('manual download'), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
      }));

  testWidgets('shows passive reminder when update is available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('shows reminder when same tag was shown over 24h ago',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      AutoUpgradeGate.updateNoticeLastTagPrefsKey: 'v1.1.0',
      AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey:
          nowMs - const Duration(hours: 25).inMilliseconds,
    });

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('skips reminder when same tag was shown within 24h',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      AutoUpgradeGate.updateNoticeLastTagPrefsKey: 'v1.1.0',
      AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey:
          nowMs - const Duration(hours: 1).inMilliseconds,
    });

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(SnackBar), findsNothing);
  });
}
