import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/diagnostics_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

class _FakeAppUpdateService extends AppUpdateService {
  _FakeAppUpdateService({
    required this.result,
  });

  final AppUpdateCheckResult result;

  int checkCalls = 0;
  int installCalls = 0;
  AppUpdateAvailability? installedUpdate;

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    return result;
  }

  @override
  Future<void> installAndRestart(AppUpdateAvailability update) async {
    installCalls += 1;
    installedUpdate = update;
  }
}

class _DiagnosticsBackend extends TestAppBackend {
  @override
  Future<String> getOrCreateDeviceId() async => 'device-test';
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required _FakeAppUpdateService service,
    Future<bool> Function(Uri uri)? launcher,
  }) {
    return tester.pumpWidget(
      AppBackendScope(
        backend: _DiagnosticsBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(
              home: DiagnosticsPage(
                updateService: service,
                externalUriLauncher: launcher,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('seamless update calls install flow', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final update = AppUpdateAvailability(
      currentVersion: '1.0.0+1',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
      installMode: AppUpdateInstallMode.seamlessRestart,
      asset: AppUpdateAsset(
        name: 'SecondLoop-windows-x64-v1.1.0.zip',
        downloadUri: Uri.parse('https://cdn.example.com/win.zip'),
      ),
    );
    final service = _FakeAppUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.0+1', update: update),
    );

    await pumpPage(tester, service: service);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('diagnostics_apply_update')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('diagnostics_check_updates')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('diagnostics_apply_update')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostics_apply_update')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(service.installCalls, 1);
    expect(service.installedUpdate?.latestTag, 'v1.1.0');
  });

  testWidgets('external update opens release URL', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
    final update = AppUpdateAvailability(
      currentVersion: '1.0.0+1',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0'),
      installMode: AppUpdateInstallMode.externalDownload,
    );
    final service = _FakeAppUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.0+1', update: update),
    );

    await pumpPage(
      tester,
      service: service,
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('diagnostics_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics_apply_update')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 0);
    expect(opened, [update.downloadUri]);
  });
}
