import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import 'support/auto_upgrade_gate_test_support.dart';

void main() {
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_prompt_update')), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('desktop update prompt uses ignore and update actions',
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_prompt_ignore')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_prompt_update')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update_prompt_ignore')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsNothing);
    expect(service.installCalls, 0);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets(
      'passive reminder stays visible beyond transient snackbar timeout',
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_prompt_update')), findsOneWidget);
  });

  testWidgets('passive reminder persists cooldown when first shown',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeAutoUpdateService(
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
      'v1.1.0',
    );
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNotNull,
    );
  });

  testWidgets('android resume does not reshow reminder within cooldown',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      AutoUpgradeGate.updateNoticeLastTagPrefsKey: 'v1.1.0',
      AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey:
          nowMs - const Duration(hours: 1).inMilliseconds,
    });
    final service = FakeAutoUpdateService(
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
    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.checkCalls, 2);
    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsNothing);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('dismissing passive reminder persists cooldown', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeAutoUpdateService(
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

    await tester.tap(find.byKey(const ValueKey('update_prompt_ignore')));
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

  testWidgets('staged update reminder explains immediate restart behavior',
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
    final service = FakeAutoUpdateService(
      canStageSilentlyForNextLaunchValue: false,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(
      find.textContaining('restart'),
      findsOneWidget,
    );
    expect(find.textContaining('next launch'), findsNothing);
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
    final service = FakeAutoUpdateService(
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

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

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
    final service = FakeAutoUpdateService(
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

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final progressDialog = find.byKey(const ValueKey('update_progress_dialog'));
    expect(progressDialog, findsOneWidget);
    expect(
      find.descendant(
        of: progressDialog,
        matching: find.text(
          'New version v1.1.0 is available. '
          'Open the update page to download it now.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Preparing update. The app will restart shortly.'),
      findsNothing,
    );
    expect(find.text('Could not open update page'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('android_update_confirm')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets(
      'linux passive reminder ignores rapid repeated primary-action taps',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final installCompleter = Completer<void>();
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
      installCompleter: installCompleter,
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final primaryAction = find.byKey(const ValueKey('update_prompt_update'));
    await tester.tap(primaryAction);
    await tester.tap(primaryAction, warnIfMissed: false);
    await tester.pump();

    expect(service.installCalls, 1);

    installCompleter.complete();
    await tester.pumpAndSettle();
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
    final service = FakeAutoUpdateService(
      throwOnInstall: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.installCalls, 1);
    expect(
        find.byKey(const ValueKey('android_update_confirm')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNotNull,
    );
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('windows seamless reminder installs from primary action',
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
    final service = FakeAutoUpdateService(
      canStageSilentlyForNextLaunchValue: true,
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 1);
    expect(service.stageCalls, 0);
    expect(service.applyStagedRestartCalls, 0);
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
    final service = FakeAutoUpdateService(
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

    await tester.tap(find.byKey(const ValueKey('update_prompt_update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(service.stageCalls, 1);
    expect(
        find.byKey(const ValueKey('android_update_confirm')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey),
      isNotNull,
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsOneWidget);
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
    final service = FakeAutoUpdateService(
      result: AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
        update: update,
      ),
    );

    await pumpGate(tester, service: service);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('update_prompt_dialog')), findsNothing);
  });
}
