import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import 'test_i18n.dart';

class _StartupFlowUpdateService extends AppUpdateService {
  _StartupFlowUpdateService({
    required this.result,
    this.throwOnApplyPending = false,
    this.applyPendingResult =
        const PendingUpdateStartupResult.noPendingUpdate(),
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;
  final PendingUpdateStartupResult applyPendingResult;

  int applyPendingCalls = 0;
  int checkCalls = 0;

  @override
  Future<PendingUpdateStartupResult> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    if (throwOnApplyPending) {
      throw StateError('apply_pending_failed');
    }
    return applyPendingResult;
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    return result;
  }
}

void main() {
  testWidgets('startup skips pending apply and does not block app startup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _StartupFlowUpdateService(
      throwOnApplyPending: true,
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            enableInDebug: true,
            child: const Scaffold(
              body: Text('home'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 1);
  });

  testWidgets('startup stops update checks while pending apply is in progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _StartupFlowUpdateService(
      applyPendingResult: const PendingUpdateStartupResult.updateInProgress(),
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            enableInDebug: true,
            child: const Scaffold(
              body: Text('home'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 0);
  });

  testWidgets(
      'startup pauses update checks when pending apply probe is inconclusive',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _StartupFlowUpdateService(
      applyPendingResult: const PendingUpdateStartupResult.probeInconclusive(),
      result: const AppUpdateCheckResult(currentVersion: '1.0.0+1'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AutoUpgradeGate(
            updateService: service,
            enableInDebug: true,
            child: const Scaffold(
              body: Text('home'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(service.applyPendingCalls, 1);
    expect(service.checkCalls, 0);
  });
}
