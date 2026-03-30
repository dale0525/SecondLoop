import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/update_event_log.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';
import 'support/app_update_service_test_support.dart';

void _writeSqVersionForAppUpdateServiceTest(Directory root, String version) {
  final currentDir = Directory('${root.path}${Platform.pathSeparator}current')
    ..createSync(recursive: true);
  File('${currentDir.path}${Platform.pathSeparator}sq.version')
      .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
<metadata>
<version>$version</version>
</metadata>
</package>
''');
}

void main() {
  group('compareReleaseTagWithCurrentVersion', () {
    test('treats higher release tag as update', () {
      expect(
        compareReleaseTagWithCurrentVersion('v1.2.0', '1.1.9'),
        greaterThan(0),
      );
    });

    test('treats fourth tag segment as newer when present', () {
      expect(
        compareReleaseTagWithCurrentVersion('v1.2.3.9', '1.2.3'),
        greaterThan(0),
      );
    });

    test('treats same version as up to date', () {
      expect(compareReleaseTagWithCurrentVersion('v2.0.0', '2.0.0'), 0);
    });
  });

  group('AppUpdateService.downloaded asset handoff', () {
    test('stages Windows seamless updates when silent staging is supported',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('update_stage_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final assetFile = File('${tempDir.path}/SecondLoop-win.nupkg');
      await assetFile.writeAsString('windows package bytes');
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
      );
      final update = AppUpdateAvailability(
        currentVersion: '1.0.0+1',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: assetFile.uri,
        ),
      );

      expect(service.canStageSilentlyForNextLaunch(update), isTrue);

      await service.stageUpdateForNextLaunch(update);

      expect(stagedClient.stagedAssets, hasLength(1));
      expect(stagedClient.stagedAssets.single, assetFile.uri);
      expect(
        logger.records
            .any((entry) => entry.type == UpdateEventType.stageSucceeded),
        isTrue,
      );
    });

    test('cleans temporary downloaded asset after Windows staging', () async {
      String? stagedPath;
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        onStageAsset: (assetDownloadUri) async {
          stagedPath = assetDownloadUri.toFilePath();
          expect(File(stagedPath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
      );

      await service.stageUpdateForNextLaunch(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.stagedNextLaunch,
          asset: AppUpdateAsset(
            name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
            downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          ),
        ),
      );

      expect(stagedPath, isNotNull);
      expect(Directory(File(stagedPath!).parent.path).existsSync(), isFalse);
    });

    test('rejects staging when update is not marked as staged-next-launch',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
      );

      await expectLater(
        () => service.stageUpdateForNextLaunch(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.externalDownload,
            asset: AppUpdateAsset(
              name: 'SecondLoop-win.msi',
              downloadUri:
                  Uri.parse('https://cdn.example.com/SecondLoop-win.msi'),
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(stagedClient.stagedAssets, isEmpty);
    });

    test('cleans temporary downloaded asset when Windows handoff sha256 fails',
        () async {
      final before = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_asset_'))
          .map((dir) => dir.path)
          .toSet();
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'tampered-nupkg',
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
              downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
              sha256: 'deadbeef',
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_asset_'))
          .map((dir) => dir.path)
          .toSet();
      expect(after, before);
    });

    test('cleans temporary downloaded asset after Windows installer handoff',
        () async {
      String? packagePath;
      var exitedCode = -1;
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        onInstallAsset: (assetDownloadUri) async {
          packagePath = assetDownloadUri.toFilePath();
          expect(File(packagePath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      await service.installAndRestart(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.seamlessRestart,
          asset: AppUpdateAsset(
            name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
            downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          ),
        ),
      );

      expect(exitedCode, 0);
      expect(packagePath, isNotNull);
      expect(Directory(File(packagePath!).parent.path).existsSync(), isFalse);
    });

    test('cleans temporary downloaded asset after macOS updater handoff',
        () async {
      String? archivePath;
      var exitedCode = -1;
      final macosClient = FakeMacosManagedUpdateClient(
        supportedInstallLocation: true,
        onInstallArchive: (archiveUri) async {
          archivePath = archiveUri.toFilePath();
          expect(File(archivePath!).existsSync(), isTrue);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        macosManagedUpdateClient: macosClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'macos-archive',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      await service.installAndRestart(
        AppUpdateAvailability(
          currentVersion: '1.0.0',
          latestTag: 'v1.1.0',
          releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
          ),
          installMode: AppUpdateInstallMode.seamlessRestart,
          asset: AppUpdateAsset(
            name: 'SecondLoop-macos-v1.1.0.app.tar.gz',
            downloadUri:
                Uri.parse('https://cdn.example.com/SecondLoop-macos.tar.gz'),
          ),
        ),
      );

      expect(exitedCode, 0);
      expect(archivePath, isNotNull);
      expect(Directory(File(archivePath!).parent.path).existsSync(), isFalse);
    });
  });

  group('AppUpdateService.installAndRestart', () {
    test(
        'reuses verified pending Windows update for exact app id and custom channel',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('update_reuse_custom_channel_');
      addTearDown(() => tempDir.delete(recursive: true));

      final updateExe =
          File('${tempDir.path}${Platform.pathSeparator}Update.exe')
            ..writeAsStringSync('stub');
      _writeSqVersionForAppUpdateServiceTest(tempDir, '1.0.0');
      File('${tempDir.path}${Platform.pathSeparator}releases.nightly.json')
          .writeAsStringSync('{}');

      final pendingFile = File(
        '${tempDir.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloopdev-1.1.0-nightly-full.nupkg',
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('windows-package');

      String? startedExecutable;
      List<String>? startedArguments;
      ProcessStartMode? startedMode;
      var exitedCode = -1;

      final stagedClient = VelopackUpdateClient(
        updateExecutablePath: updateExe.path,
        appId: 'com.secondloop.secondloopdev',
        processStarter: (executable, arguments,
            {mode = ProcessStartMode.normal}) async {
          startedExecutable = executable;
          startedArguments = List<String>.from(arguments);
          startedMode = mode;
          return Process.start(
              Platform.resolvedExecutable, const ['--version']);
        },
      );
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => throw StateError('should_not_download:$uri'),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloopdev-1.1.0-nightly-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win-nightly.nupkg'),
          sha256: await sha256FileHexForTest(pendingFile),
        ),
      );

      await service.installAndRestart(update);

      expect(startedExecutable, updateExe.path);
      expect(startedArguments, isNotNull);
      expect(startedArguments,
          containsAllInOrder(const ['apply', '--silent', '--restart']));
      expect(startedArguments, isNot(contains('--package')));
      expect(startedMode, ProcessStartMode.detached);
      expect(exitedCode, 0);
    });

    test('applies staged Windows update without re-downloading', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_reuse_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pendingFile = File(
        '${tempDir.path}${Platform.pathSeparator}com.secondloop.secondloop-1.1.0-full.nupkg',
      );
      await pendingFile.writeAsString('windows-package');
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: true,
        pendingUpdateVersionValue: '1.1.0',
        pendingUpdatePackagePathValue: pendingFile.path,
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => throw StateError('should_not_download:$uri'),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          sha256:
              '5399ae01b97abc674bd372c0621aeb3d5ff463e35dc90dc4c4186deccdab9e61',
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.installCalls, 0);
      expect(stagedClient.applyPendingAndRestartCalls, 1);
      expect(exitedCode, 0);
    });

    test('re-downloads Windows update when pending package hash mismatches',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('update_reuse_bad_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pendingFile = File(
        '${tempDir.path}${Platform.pathSeparator}com.secondloop.secondloop-1.1.0-full.nupkg',
      );
      await pendingFile.writeAsString('stale-package');

      String? installedPath;
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: true,
        pendingUpdateVersionValue: '1.1.0',
        pendingUpdatePackagePathValue: pendingFile.path,
        onInstallAsset: (assetDownloadUri) async {
          installedPath = assetDownloadUri.toFilePath();
        },
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          sha256:
              '5399ae01b97abc674bd372c0621aeb3d5ff463e35dc90dc4c4186deccdab9e61',
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.applyPendingAndRestartCalls, 0);
      expect(stagedClient.installCalls, 1);
      expect(installedPath, isNotNull);
      expect(exitedCode, 0);
    });

    test('does not reuse prerelease pending package for final Windows release',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('update_reuse_prerelease_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pendingFile = File(
        '${tempDir.path}${Platform.pathSeparator}com.secondloop.secondloop-1.1.0-beta-full.nupkg',
      );
      await pendingFile.writeAsString('windows-package');

      String? installedPath;
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: true,
        pendingUpdateVersionValue: '1.1.0-beta',
        pendingUpdatePackagePathValue: pendingFile.path,
        onInstallAsset: (assetDownloadUri) async {
          installedPath = assetDownloadUri.toFilePath();
        },
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
          sha256:
              '5399ae01b97abc674bd372c0621aeb3d5ff463e35dc90dc4c4186deccdab9e61',
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.applyPendingAndRestartCalls, 0);
      expect(stagedClient.installCalls, 1);
      expect(installedPath, isNotNull);
      expect(exitedCode, 0);
    });

    test(
        'downloads requested Windows update instead of reusing stale pending package',
        () async {
      String? installedPath;
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: true,
        pendingUpdateVersionValue: '1.1.0',
        onInstallAsset: (assetDownloadUri) async {
          installedPath = assetDownloadUri.toFilePath();
          expect(File(installedPath!).existsSync(), isTrue);
        },
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'windows-package',
          ),
        ),
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.2.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.2.0-full.nupkg',
          downloadUri: Uri.parse('https://cdn.example.com/win-1.2.0.nupkg'),
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.applyPendingAndRestartCalls, 0);
      expect(stagedClient.installCalls, 1);
      expect(installedPath, isNotNull);
      expect(Directory(File(installedPath!).parent.path).existsSync(), isFalse);
      expect(exitedCode, 0);
    });

    test('delegates Windows install to Velopack and exits', () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      final logger = InMemoryUpdateEventLogger();
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
          downloadUri: Uri.parse('file:///tmp/SecondLoop-1.1.0.nupkg'),
        ),
      );

      await service.installAndRestart(update);

      expect(stagedClient.installCalls, 1);
      expect(stagedClient.installedAssets.single.toString(),
          'file:///tmp/SecondLoop-1.1.0.nupkg');
      expect(exitedCode, 0);
      expect(
        logger.records
            .any((entry) => entry.type == UpdateEventType.installDispatched),
        isTrue,
      );
    });

    test('verifies sha256 before Linux seamless install', () async {
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: 'tampered-linux-archive',
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
              downloadUri: Uri.parse(
                'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
              ),
              sha256: 'abc123',
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('accepts file URI for Linux seamless install without HTTP download',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('linux_file_update_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      });

      final archiveFile =
          File('${tempDir.path}/SecondLoop-linux-x64-v1.1.0.tar.gz');
      await archiveFile.writeAsString('not-a-valid-tar-archive');
      final expectedSha = await sha256FileHexForTest(archiveFile);
      var requestedUris = 0;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        httpClient: _FakeHttpClient(
          handler: (uri) {
            requestedUris += 1;
            throw StateError('should_not_download:$uri');
          },
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
              downloadUri: archiveFile.uri,
              sha256: expectedSha,
            ),
          ),
        ),
        throwsA(anything),
      );

      expect(requestedUris, 0);
    });

    test('cleans Linux tempRoot when install throws before script handoff',
        () async {
      const body = 'not-a-valid-tar-archive';
      final tempHashDir = await Directory.systemTemp.createTemp('linux_hash_');
      addTearDown(() => tempHashDir.delete(recursive: true));
      final hashFile = File('${tempHashDir.path}/payload.tar.gz');
      await hashFile.writeAsString(body);
      final expectedSha = await sha256FileHexForTest(hashFile);
      final before = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_update_'))
          .map((dir) => dir.path)
          .toSet();
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.linux,
        httpClient: _FakeHttpClient(
          handler: (uri) => const _FakeHttpResponse(
            statusCode: 200,
            body: body,
          ),
        ),
        processExit: (_) {},
      );

      await expectLater(
        () => service.installAndRestart(
          AppUpdateAvailability(
            currentVersion: '1.0.0',
            latestTag: 'v1.1.0',
            releasePageUri: Uri.parse(
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
            ),
            installMode: AppUpdateInstallMode.seamlessRestart,
            asset: AppUpdateAsset(
              name: 'SecondLoop-linux-x64-v1.1.0.tar.gz',
              downloadUri: Uri.parse(
                'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
              ),
              sha256: expectedSha,
            ),
          ),
        ),
        throwsA(anything),
      );

      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              dir.path.contains('${Platform.pathSeparator}secondloop_update_'))
          .map((dir) => dir.path)
          .toSet();
      final created = after.difference(before);
      for (final path in created) {
        try {
          final dir = Directory(path);
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
      if (Platform.isWindows) {
        return;
      }
      expect(after, before);
    });

    test('delegates macOS install to managed client and exits', () async {
      final macosClient =
          FakeMacosManagedUpdateClient(supportedInstallLocation: true);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.macos,
        macosManagedUpdateClient: macosClient,
        processExit: (code) => exitedCode = code,
      );

      final update = AppUpdateAvailability(
        currentVersion: '1.0.0',
        latestTag: 'v1.1.0',
        releasePageUri: Uri.parse(
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
        ),
        installMode: AppUpdateInstallMode.seamlessRestart,
        asset: AppUpdateAsset(
          name: 'SecondLoop-macos-v1.1.0.app.tar.gz',
          downloadUri:
              Uri.parse('file:///tmp/SecondLoop-macos-v1.1.0.app.tar.gz'),
        ),
      );

      await service.installAndRestart(update);

      expect(macosClient.installCalls, 1);
      expect(macosClient.installedAssets.single.toString(),
          'file:///tmp/SecondLoop-macos-v1.1.0.app.tar.gz');
      expect(exitedCode, 0);
    });
  });

  group('AppUpdateService.applyPendingUpdateOnStartup', () {
    test('records pending apply dispatch before exiting current process',
        () async {
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateDispatched(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 1);
      expect(stagedClient.lastStartupWaitPid, pid);
      expect(applied.status, PendingUpdateStartupStatus.dispatched);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isTrue,
      );
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplySucceeded,
        ),
        isFalse,
      );
    });

    test('still exits when dispatch event logging fails', () async {
      final logger = ThrowingUpdateEventLogger(
        failOnType: UpdateEventType.pendingApplyDispatched,
      );
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateDispatched(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(applied.status, PendingUpdateStartupStatus.dispatched);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyStarted,
        ),
        isTrue,
      );
    });

    test('skips dispatch event when no pending update is available', () async {
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingUpdateAvailable: false,
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 1);
      expect(applied.status, PendingUpdateStartupStatus.none);
      expect(exitedCode, -1);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isFalse,
      );
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyStarted,
        ),
        isFalse,
      );
    });

    test('skips apply when staged runtime is unavailable', () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: false);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(stagedClient.applyPendingCalls, 0);
      expect(applied.status, PendingUpdateStartupStatus.none);
      expect(exitedCode, -1);
    });

    test('exits when pending Windows apply is already in progress', () async {
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.updateInProgress(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(applied.status, PendingUpdateStartupStatus.inProgress);
      expect(exitedCode, 0);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isFalse,
      );
    });

    test('does not exit when pending Windows apply probe is inconclusive',
        () async {
      final logger = InMemoryUpdateEventLogger();
      final stagedClient = FakeWindowsStagedUpdateClient(
        available: true,
        pendingApplyStartupResult:
            const PendingUpdateStartupResult.probeInconclusive(),
      );
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        updateEventLogger: logger,
        processExit: (code) => exitedCode = code,
      );

      final applied = await service.applyPendingUpdateOnStartup();

      expect(applied.status, PendingUpdateStartupStatus.probeInconclusive);
      expect(exitedCode, -1);
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyStarted,
        ),
        isFalse,
      );
      expect(
        logger.records.any(
          (entry) => entry.type == UpdateEventType.pendingApplyDispatched,
        ),
        isFalse,
      );
    });
  });

  group('AppUpdateService.applyStagedUpdateAndRestart', () {
    test('restarts into staged Windows update when runtime is available',
        () async {
      final stagedClient = FakeWindowsStagedUpdateClient(available: true);
      var exitedCode = -1;
      final service = AppUpdateService(
        platformOverride: AppUpdatePlatform.windows,
        windowsStagedUpdateClient: stagedClient,
        processExit: (code) => exitedCode = code,
      );

      await service.applyStagedUpdateAndRestart();

      expect(stagedClient.applyPendingAndRestartCalls, 1);
      expect(exitedCode, 0);
    });
  });
}

final class _FakeHttpResponse {
  const _FakeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.handler});

  final _FakeHttpResponse Function(Uri uri) handler;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final response = handler(url);
    return _FakeHttpClientRequest(
      response: _FakeHttpClientResponse(
        statusCode: response.statusCode,
        body: response.body,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.response});

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required String body})
      : _stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);

  final Stream<List<int>> _stream;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
