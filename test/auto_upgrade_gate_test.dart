import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import 'test_i18n.dart';

class _FakeAutoUpdateService extends AppUpdateService {
  _FakeAutoUpdateService({
    required this.result,
  });

  final AppUpdateCheckResult result;

  int checkCalls = 0;
  int installCalls = 0;
  AppUpdateAvailability? installed;

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
}

void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    required _FakeAutoUpdateService service,
  }) {
    return tester.pumpWidget(
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
  }

  testWidgets('auto installs seamless update on startup', (tester) async {
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-windows-x64-v1.1.0.zip',
        downloadUri: Uri.parse('https://cdn.example.com/win.zip'),
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
    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');
  });

  testWidgets('skips install when only external download is available',
      (tester) async {
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
  });
}
