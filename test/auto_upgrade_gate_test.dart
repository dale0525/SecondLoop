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
    this.applyPendingResult =
        const PendingUpdateStartupResult.noPendingUpdate(),
    this.throwOnInstall = false,
    this.throwOnStage = false,
    this.releaseRepoValue = 'dale0525/SecondLoop',
    this.canStageSilentlyForNextLaunchValue = false,
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;
  final PendingUpdateStartupResult applyPendingResult;
  final bool throwOnInstall;
  final bool throwOnStage;
  final String releaseRepoValue;
  final bool canStageSilentlyForNextLaunchValue;

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
  Uri get fallbackReleasePageUri =>
      AutoUpgradeGate.fallbackUpdateUri(releaseRepo: releaseRepoValue);

  @override
  bool canStageSilentlyForNextLaunch(AppUpdateAvailability update) {
    return canStageSilentlyForNextLaunchValue;
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    return result;
  }

  @override
  Future<void> installAndRestart(AppUpdateAvailability update) async {
    installCalls += 1;
    if (throwOnInstall) {
      throw StateError('install_failed');
    }
    installed = update;
  }

  @override
  Future<void> stageUpdateForNextLaunch(AppUpdateAvailability update) async {
    stageCalls += 1;
    if (throwOnStage) {
      throw StateError('stage_failed');
    }
    staged = update;
  }

  @override
  Future<PendingUpdateStartupResult> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    if (throwOnApplyPending) {
      throw StateError('apply_pending_failed');
    }
    return applyPendingResult;
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

  testWidgets('starts auto upgrade work from the first post-frame callback',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );

    await pumpGate(tester, service: service);

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 1);
  });

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
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
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

  testWidgets(
      'windows seamless update keeps in-app reminder when staging fails',
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
      canStageSilentlyForNextLaunchValue: true,
      throwOnStage: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.installCalls, 0);
    expect(service.stageCalls, 1);
    expect(service.applyPendingCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

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
      canStageSilentlyForNextLaunchValue: true,
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

  testWidgets(
      'windows seamless update does not stage when silent staging is unsupported',
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
      canStageSilentlyForNextLaunchValue: false,
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
    expect(UpdateBadgePrefs.value.value, 'v1.1.0');
    expect(find.byType(SnackBar), findsOneWidget);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'windows staged-next-launch update is passively staged on startup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
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
    final service = _FakeAutoUpdateService(
      canStageSilentlyForNextLaunchValue: true,
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

  testWidgets('windows skips update check after pending apply succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();

    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.3.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.3.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.3.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
      ),
    );
    final service = _FakeAutoUpdateService(
      applyPendingResult: const PendingUpdateStartupResult.updateDispatched(),
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 0);
    expect(service.stageCalls, 0);
    expect(find.byType(SnackBar), findsNothing);
    expect(UpdateBadgePrefs.value.value, isNull);
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

  testWidgets(
      'pending apply failure still publishes the available update badge',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.4.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.4.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.4.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
      ),
    );
    final service = _FakeAutoUpdateService(
      throwOnApplyPending: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 1);
    expect(UpdateBadgePrefs.value.value, 'v1.4.0');
    expect(find.textContaining('Auto update failed'), findsOneWidget);
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

  testWidgets('skips update check when pending apply is already in progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      applyPendingResult: const PendingUpdateStartupResult.updateInProgress(),
      result: const AppUpdateCheckResult(currentVersion: '1.0.1+99'),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 0);
    expect(find.byType(SnackBar), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'skips update work but still shows app when pending apply probe is inconclusive',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      applyPendingResult: const PendingUpdateStartupResult.probeInconclusive(),
      result: const AppUpdateCheckResult(currentVersion: '1.0.1+99'),
    );

    await pumpGate(tester, service: service);
    await tester.pumpAndSettle();

    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 0);
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

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
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Manual update'), findsOneWidget);
  });

  testWidgets('passive reminder does not persist cooldown before interaction',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: AppUpdateAvailability(
          currentVersion: '1.0.1+99',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.externalDownload,
        ),
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AutoUpgradeGate.updateNoticeLastTagPrefsKey),
      isNull,
    );
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNull,
    );
  });

  testWidgets('dismissing passive reminder persists cooldown', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: AppUpdateAvailability(
          currentVersion: '1.0.1+99',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.externalDownload,
        ),
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_secondary_action')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AutoUpgradeGate.updateNoticeLastTagPrefsKey),
      'v1.1.0',
    );
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNotNull,
    );
  });

  testWidgets('staged update reminder explains next-launch apply behavior',
      (tester) async {
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
    final service = _FakeAutoUpdateService(
      canStageSilentlyForNextLaunchValue: false,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Prepare update'), findsOneWidget);
    expect(
      find.textContaining('apply next launch'),
      findsOneWidget,
    );
    expect(find.textContaining('download it now'), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets('passive reminder opens release page from primary action',
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
    );
    final service = _FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(
      tester,
      service: service,
      externalUriLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pumpAndSettle();

    expect(opened, <Uri>[update.releasePageUri]);
    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
  });

  testWidgets('manual update action keeps retry controls when opening fails',
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

    await pumpGate(
      tester,
      service: service,
      externalUriLauncher: (uri) async => false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open update page'), findsOneWidget);
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Manual update'), findsOneWidget);
  });

  testWidgets('linux passive reminder installs immediately from primary action',
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

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('linux passive reminder keeps retry controls when install fails',
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
        name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
        downloadUri: Uri.parse('https://cdn.example.com/linux.tar.gz'),
      ),
    );
    final service = _FakeAutoUpdateService(
      throwOnInstall: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.installCalls, 1);
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNull,
    );
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets(
      'windows staged reminder applies staged update from primary action',
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
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
      ),
    );
    final service = _FakeAutoUpdateService(
      canStageSilentlyForNextLaunchValue: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pumpAndSettle();

    expect(service.stageCalls, 1);
    expect(service.applyStagedRestartCalls, 1);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'windows staged-next-launch action keeps retry controls on failure',
      (tester) async {
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
    final service = _FakeAutoUpdateService(
      throwOnStage: true,
      canStageSilentlyForNextLaunchValue: false,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester
        .tap(find.byKey(const ValueKey('update_notice_primary_action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.stageCalls, 1);
    expect(find.byKey(const ValueKey('update_notice_primary_action')),
        findsOneWidget);
    expect(find.text('Prepare update'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNull,
    );
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

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
