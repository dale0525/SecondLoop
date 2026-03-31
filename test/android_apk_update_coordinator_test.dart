import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/app_update_service.dart';

class _FakeDownloader implements AndroidApkDownloader {
  _FakeDownloader({required this.bytes});

  final List<int> bytes;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    onProgress(
      const AndroidApkDownloadProgress(receivedBytes: 10, totalBytes: 100),
    );
    final file =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

class _FakeInstaller implements AndroidApkInstaller {
  _FakeInstaller({this.error});

  final Object? error;
  int installCalls = 0;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    if (error != null) {
      throw error!;
    }
  }
}

void main() {
  test('verifies sha256 before installing apk', () async {
    const bytes = <int>[1, 2, 3, 4];
    final tempFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}android-update-coordinator.apk');
    await tempFile.writeAsBytes(bytes, flush: true);
    addTearDown(() async {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    });

    final digest = await AndroidApkUpdateCoordinator.sha256FileHex(tempFile);
    final installer = _FakeInstaller();
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: bytes),
      installer: installer,
    );

    await coordinator.performUpdate(
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a.apk',
        downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
        sha256: digest,
      ),
      onProgress: (_) {},
    );

    expect(installer.installCalls, 1);
  });

  test('reports integrity-check failure before install', () async {
    final installer = _FakeInstaller();
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: const <int>[9, 9, 9]),
      installer: installer,
    );

    await expectLater(
      () => coordinator.performUpdate(
        asset: AppUpdateAsset(
          name: 'SecondLoop-android-arm64-v8a.apk',
          downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
          sha256: 'deadbeef',
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<AndroidApkUpdateException>().having(
          (error) => error.type,
          'type',
          AndroidApkUpdateFailureType.integrityCheck,
        ),
      ),
    );
    expect(installer.installCalls, 0);
  });

  test('reports install-launch failure separately', () async {
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: const <int>[1, 2, 3]),
      installer: _FakeInstaller(error: StateError('installer_failed')),
    );

    await expectLater(
      () => coordinator.performUpdate(
        asset: AppUpdateAsset(
          name: 'SecondLoop-android-arm64-v8a.apk',
          downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<AndroidApkUpdateException>().having(
          (error) => error.type,
          'type',
          AndroidApkUpdateFailureType.installLaunch,
        ),
      ),
    );
  });
}
