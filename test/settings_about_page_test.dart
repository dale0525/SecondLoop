import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/about_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

class _FakeAboutUpdateService extends AppUpdateService {
  _FakeAboutUpdateService({required this.result});

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
  testWidgets('Settings support section includes About entry', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aboutEntry = find.byKey(const ValueKey('settings_about'));
    await tester.dragUntilVisible(
      aboutEntry,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(aboutEntry, findsOneWidget);

    await tester.tap(aboutEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('About page shows version and update actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
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
    final service = _FakeAboutUpdateService(
      result: AppUpdateCheckResult(currentVersion: '1.0.1+99', update: update),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            runtimeVersionLoader: () async =>
                const AppRuntimeVersion(version: '1.0.1', buildNumber: '99'),
            externalUriLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_open_homepage')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_manual_update')), findsOneWidget);
    expect(find.textContaining('1.0.1+99'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.textContaining('v1.1.0'), findsWidgets);
    expect(find.byKey(const ValueKey('about_auto_update')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_auto_update')));
    await tester.pumpAndSettle();
    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');

    await tester.tap(find.byKey(const ValueKey('about_manual_update')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), update.downloadUri.toString());

    await tester.tap(find.byKey(const ValueKey('about_open_homepage')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://secondloop.app');
  });
}
