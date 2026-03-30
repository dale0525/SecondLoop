import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

void main() {
  test('checkForUpdates prefers exact Windows app id asset from release assets',
      () async {
    final stagedClient = VelopackUpdateClient(
      updateExecutablePath: _stubUpdateExePath(),
      appId: 'com.secondloop.secondloopdev',
    );
    final service = AppUpdateService(
      platformOverride: AppUpdatePlatform.windows,
      releaseModeOverride: true,
      windowsStagedUpdateClient: stagedClient,
      releaseJsonFetcher: (_) async => <String, Object?>{
        'tag_name': 'v1.1.0',
        'html_url': 'https://example.com/releases/v1.1.0',
        'assets': <Object?>[
          <String, Object?>{
            'name': 'com.secondloop.secondloop-1.1.0-full.nupkg',
            'browser_download_url': 'https://cdn.example.com/prod.nupkg',
            'sha256': 'prod',
          },
          <String, Object?>{
            'name': 'com.secondloop.secondloopdev-1.1.0-full.nupkg',
            'browser_download_url': 'https://cdn.example.com/dev.nupkg',
            'sha256': 'dev',
          },
        ],
      },
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(result.update!.asset?.name,
        'com.secondloop.secondloopdev-1.1.0-full.nupkg');
    expect(
      result.update!.installMode,
      AppUpdateInstallMode.seamlessRestart,
    );
  });

  test('checkForUpdates prefers exact Windows app id asset from manifest',
      () async {
    final stagedClient = VelopackUpdateClient(
      updateExecutablePath: _stubUpdateExePath(),
      appId: 'com.secondloop.secondloopdev',
    );
    final service = AppUpdateService(
      platformOverride: AppUpdatePlatform.windows,
      releaseModeOverride: true,
      windowsStagedUpdateClient: stagedClient,
      releaseJsonFetcher: (_) async => <String, Object?>{
        'version': '1.1.0',
        'release_page_url': 'https://example.com/releases/v1.1.0',
        'platforms': <String, Object?>{
          'windows-x64': <String, Object?>{
            'name': 'com.secondloop.secondloopdev-1.1.0-full.nupkg',
            'package_url': 'https://cdn.example.com/dev.nupkg',
            'sha256': 'dev',
            'install_mode': 'velopack',
            'app_id': 'com.secondloop.secondloopdev',
          },
        },
      },
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(result.update!.asset?.name,
        'com.secondloop.secondloopdev-1.1.0-full.nupkg');
    expect(
      result.update!.installMode,
      AppUpdateInstallMode.seamlessRestart,
    );
  });
}

String _stubUpdateExePath() {
  final root = Directory.systemTemp.createTempSync('app_update_identity_');
  addTearDown(() => root.delete(recursive: true));
  final updateExe = File('${root.path}${Platform.pathSeparator}Update.exe')
    ..writeAsStringSync('stub');
  Directory('${root.path}${Platform.pathSeparator}current').createSync();
  File('${root.path}${Platform.pathSeparator}current${Platform.pathSeparator}sq.version')
      .writeAsStringSync('1.0.0');
  return updateExe.path;
}
