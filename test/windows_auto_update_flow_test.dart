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
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;

  int applyPendingCalls = 0;
  int checkCalls = 0;

  @override
  Future<void> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    if (throwOnApplyPending) {
      throw StateError('apply_pending_failed');
    }
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
    expect(service.applyPendingCalls, 0);
    expect(service.checkCalls, 1);
  });
}
