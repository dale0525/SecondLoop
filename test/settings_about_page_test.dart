import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/features/settings/about_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/features/settings/settings_ui.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

const _fakeAndroidApkSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class _FakeAboutUpdateService extends AppUpdateService {
  _FakeAboutUpdateService({
    required this.result,
  });

  AppUpdateCheckResult result;
  Object? throwOnCheck;

  int checkCalls = 0;
  int installCalls = 0;
  int stageCalls = 0;
  int applyStagedRestartCalls = 0;
  AppUpdateAvailability? installed;
  AppUpdateAvailability? staged;

  @override
  String get releaseRepo => 'dale0525/SecondLoop';

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    if (throwOnCheck != null) {
      throw throwOnCheck!;
    }
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
  Future<void> applyStagedUpdateAndRestart() async {
    applyStagedRestartCalls += 1;
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

    expect(find.byType(SettingsPageShell), findsOneWidget);
    expect(find.byType(SettingsSection), findsWidgets);
    expect(find.byKey(const ValueKey('about_open_homepage')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);
    expect(find.textContaining('1.0.1+99'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.textContaining('v1.1.0'), findsWidgets);
    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.text('Update now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');

    await tester.tap(find.byKey(const ValueKey('about_open_homepage')));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://secondloop.app');
  });

  testWidgets('About page update section keeps one button and updates from it',
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCalls, 1);
    expect(service.installCalls, 1);
    expect(service.installed?.latestTag, 'v1.1.0');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('About page immediate update opens release page when needed',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
    final update = AppUpdateAvailability(
      currentVersion: '1.0.1+99',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.externalDownload,
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
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

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(
      opened.single.toString(),
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
    );
    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets(
      'About page opens release page for Android apk when in-app install is unavailable',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri:
            Uri.parse('https://cdn.example.com/SecondLoop-android.apk'),
        sha256: _fakeAndroidApkSha256,
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

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(
      opened.single.toString(),
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
    );

    debugDefaultTargetPlatformOverride = oldPlatform;
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('About page stages and applies update from the single button',
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();
    expect(find.textContaining('restart'), findsOneWidget);
    expect(find.textContaining('next launch'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.installCalls, 0);
    expect(service.stageCalls, 1);
    expect(service.applyStagedRestartCalls, 1);
    expect(service.staged?.latestTag, 'v1.1.0');
  });

  testWidgets(
      'About page shows managed update action on Windows when available',
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
        downloadUri: Uri.parse('https://cdn.example.com/SecondLoop-win.nupkg'),
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.text('Update now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.installCalls, 1);
    expect(service.stageCalls, 0);
    expect(service.installed?.latestTag, 'v1.1.0');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets(
      'About page uses single update button for Windows external download',
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
      asset: AppUpdateAsset(
        name: 'SecondLoop-win.msi',
        downloadUri: Uri.parse('https://cdn.example.com/SecondLoop-win.msi'),
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

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.byKey(const ValueKey('about_manual_update')), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.installCalls, 0);
    expect(service.stageCalls, 0);
    expect(
      opened.single.toString(),
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
    );
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
      }));

  testWidgets('About page retries update check after check failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final opened = <Uri>[];
    final service = _FakeAboutUpdateService(
      result: const AppUpdateCheckResult(
        currentVersion: '1.0.1+99',
      ),
    );
    service.throwOnCheck = StateError('network_down');

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

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about_auto_update')), findsNothing);
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Manual update'), findsOneWidget);
    expect(service.checkCalls, 1);

    await tester.tap(find.text('Manual update'));
    await tester.pumpAndSettle();
    expect(
      opened.single.toString(),
      'https://github.com/dale0525/SecondLoop/releases/latest',
    );

    service.throwOnCheck = null;
    service.result = const AppUpdateCheckResult(currentVersion: '1.0.1+99');

    await tester.tap(find.byKey(const ValueKey('about_check_updates')));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 2);
    expect(find.text("You're on the latest version."), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
  });
}
