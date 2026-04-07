import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import '../test_i18n.dart';

class FakeAutoUpdateService extends AppUpdateService {
  FakeAutoUpdateService({
    required this.result,
    this.throwOnApplyPending = false,
    this.applyPendingResult =
        const PendingUpdateStartupResult.noPendingUpdate(),
    this.throwOnInstall = false,
    this.throwOnStage = false,
    this.releaseRepoValue = 'dale0525/SecondLoop',
    this.canStageSilentlyForNextLaunchValue = false,
    this.installCompleter,
    this.stageCompleter,
    this.applyStagedRestartCompleter,
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;
  final PendingUpdateStartupResult applyPendingResult;
  final bool throwOnInstall;
  final bool throwOnStage;
  final String releaseRepoValue;
  final bool canStageSilentlyForNextLaunchValue;
  final Completer<void>? installCompleter;
  final Completer<void>? stageCompleter;
  final Completer<void>? applyStagedRestartCompleter;

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
    final pending = installCompleter;
    if (pending != null) {
      await pending.future;
    }
    if (throwOnInstall) {
      throw StateError('install_failed');
    }
    installed = update;
  }

  @override
  Future<void> stageUpdateForNextLaunch(AppUpdateAvailability update) async {
    stageCalls += 1;
    final pending = stageCompleter;
    if (pending != null) {
      await pending.future;
    }
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
    final pending = applyStagedRestartCompleter;
    if (pending != null) {
      await pending.future;
    }
  }
}

Future<void> pumpGate(
  WidgetTester tester, {
  required FakeAutoUpdateService service,
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
