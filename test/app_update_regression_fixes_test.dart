import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import 'support/app_update_service_test_support.dart';
import 'test_i18n.dart';

void main() {
  group('app update regression fixes', () {
    test('prefers exact Windows MSI fallback for current app identity',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: false,
        appIdValue: 'com.secondloop.secondloopdev',
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        windowsStagedUpdateClient: stagedClient,
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'version': '1.1.0',
          'release_page_url': 'https://example.com/releases/v1.1.0',
          'platforms': <String, Object?>{
            'windows-x64': <String, Object?>{
              'name': 'com.secondloop.secondloopdev-1.1.0-devwin-full.nupkg',
              'package_url': 'https://cdn.example.com/dev.nupkg',
              'sha256': 'abc123',
            },
          },
          'assets': <Object?>[
            <String, Object?>{
              'name': 'SecondLoop-win.msi',
              'browser_download_url': 'https://cdn.example.com/prod.msi',
            },
            <String, Object?>{
              'name': 'SecondLoop Dev-win.msi',
              'browser_download_url': 'https://cdn.example.com/dev.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.installMode, AppUpdateInstallMode.externalDownload);
      expect(result.update!.asset?.name, 'SecondLoop Dev-win.msi');
      expect(result.update!.downloadUri.toString(),
          'https://cdn.example.com/dev.msi');
    });

    test(
        'uses release api origin as fallback release page for self-hosted feeds',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        releaseModeOverride: true,
        releaseApiOriginOverride: 'https://updates.example.com/custom/base',
        releaseRepoOverride: 'dale0525/SecondLoop',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'version': '1.1.0',
          'platforms': <String, Object?>{
            'linux-x64': <String, Object?>{
              'install_mode': 'bundle-tar-gz',
              'archive_url':
                  'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
              'sha256': 'linuxsha',
            },
          },
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(
        result.update!.releasePageUri,
        Uri.parse('https://updates.example.com/custom/base'),
      );
    });

    test(
        'unknown Windows architecture prefers neutral MSI instead of arm64-only asset order',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentArchitectureOverride: 'mystery-cpu',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'version': '1.1.0',
          'release_page_url': 'https://example.com/releases/v1.1.0',
          'assets': <Object?>[
            <String, Object?>{
              'name': 'SecondLoop-win-arm64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/arm64.msi',
            },
            <String, Object?>{
              'name': 'SecondLoop-win.msi',
              'browser_download_url': 'https://cdn.example.com/neutral.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.name, 'SecondLoop-win.msi');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/neutral.msi',
      );
    });

    test('unknown Windows architecture still falls back to x64 installer',
        () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        releaseModeOverride: true,
        currentArchitectureOverride: 'mystery-cpu',
        currentVersionLoader: () async =>
            const AppRuntimeVersion(version: '1.0.0', buildNumber: '7'),
        releaseJsonFetcher: (_) async => <String, Object?>{
          'version': '1.1.0',
          'release_page_url': 'https://example.com/releases/v1.1.0',
          'assets': <Object?>[
            <String, Object?>{
              'name': 'SecondLoop-win-x64-v1.1.0.msi',
              'browser_download_url': 'https://cdn.example.com/x64.msi',
            },
          ],
        },
      );

      final result = await service.checkForUpdates();

      expect(result.update, isNotNull);
      expect(result.update!.asset?.name, 'SecondLoop-win-x64-v1.1.0.msi');
      expect(
        result.update!.downloadUri.toString(),
        'https://cdn.example.com/x64.msi',
      );
    });

    testWidgets(
        'manual fallback notice opens update release page from result when apply pending fails',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final update = AppUpdateAvailability(
        currentVersion: '1.0.1+99',
        latestTag: 'v1.4.0',
        releasePageUri: Uri.parse('https://updates.example.com/custom/base'),
        installMode: AppUpdateInstallMode.externalDownload,
      );
      final service = _FakeAutoUpdateServiceForRegression(
        throwOnApplyPending: true,
        result: AppUpdateCheckResult(
          currentVersion: '1.0.1+99',
          update: update,
        ),
      );
      Uri? openedUri;

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AutoUpgradeGate(
              updateService: service,
              enableInDebug: true,
              externalUriLauncher: (uri) async {
                openedUri = uri;
                return true;
              },
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manual update'), findsOneWidget);
      await tester.tap(find.text('Manual update'));
      await tester.pumpAndSettle();

      expect(
        openedUri,
        Uri.parse('https://updates.example.com/custom/base'),
      );
    });
  });
}

class _FakeAutoUpdateServiceForRegression extends AppUpdateService {
  _FakeAutoUpdateServiceForRegression({
    required this.result,
    this.throwOnApplyPending = false,
  });

  final AppUpdateCheckResult result;
  final bool throwOnApplyPending;

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async => result;

  @override
  Future<PendingUpdateStartupResult> applyPendingUpdateOnStartup() async {
    if (throwOnApplyPending) {
      throw StateError('apply_pending_failed');
    }
    return const PendingUpdateStartupResult.noPendingUpdate();
  }
}
