import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/app_update_service.dart';

class _FakeDownloader implements AndroidApkDownloader {
  _FakeDownloader({required this.bytes});

  final List<int> bytes;
  int downloadCalls = 0;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    downloadCalls += 1;
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

  Object? error;
  int installCalls = 0;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    if (error != null) {
      throw error!;
    }
  }
}

class _FakeCachedInstaller implements AndroidApkInstaller {
  _FakeCachedInstaller({this.error});

  Object? error;
  int installCalls = 0;
  String? lastPath;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    lastPath = apkPath;
    if (error != null) {
      throw error!;
    }
  }
}

class _CancellingInstaller implements AndroidApkInstaller {
  _CancellingInstaller(this.cancelToken);

  final AndroidApkDownloadCancelToken cancelToken;
  int installCalls = 0;

  @override
  Future<void> installApk({required String apkPath}) async {
    installCalls += 1;
    cancelToken.cancel();
  }
}

void main() {
  setUp(() {
    AndroidApkUpdateCoordinator.clearCacheForTest();
  });

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

    final downloadedFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}SecondLoop-android-arm64-v8a.apk',
    );
    expect(downloadedFile.existsSync(), isFalse);
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

  test('does not launch installer after cancellation', () async {
    final cancelToken = AndroidApkDownloadCancelToken();
    final installer = _CancellingInstaller(cancelToken);
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: const <int>[1, 2, 3]),
      installer: installer,
    );

    cancelToken.cancel();

    await expectLater(
      () => coordinator.performUpdate(
        asset: AppUpdateAsset(
          name: 'SecondLoop-android-arm64-v8a.apk',
          downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
          sha256:
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
        onProgress: (_) {},
        cancelToken: cancelToken,
      ),
      throwsA(isA<AndroidApkDownloadCancelledException>()),
    );
    expect(installer.installCalls, 0);
  });

  test('re-downloads apk for repeated install launch retries without sha256',
      () async {
    final downloader = _FakeDownloader(bytes: const <int>[1, 2, 3]);
    final installer = _FakeCachedInstaller(
      error: StateError('android_apk_install_not_started'),
    );
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: downloader,
      installer: installer,
    );
    final asset = AppUpdateAsset(
      name: 'SecondLoop-android-arm64-v8a.apk',
      downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
    );

    await expectLater(
      () => coordinator.performUpdate(asset: asset, onProgress: (_) {}),
      throwsA(
        isA<AndroidApkUpdateException>().having(
          (error) => error.type,
          'type',
          AndroidApkUpdateFailureType.installLaunch,
        ),
      ),
    );
    expect(installer.lastPath, isNotNull);
    final firstPath = installer.lastPath;

    installer.error = null;
    await coordinator.performUpdate(asset: asset, onProgress: (_) {});

    expect(installer.installCalls, 2);
    expect(installer.lastPath, firstPath);
    expect(downloader.downloadCalls, 2);
  });

  test('reuses cached apk only when sha256 is provided', () async {
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}android-update-coordinator-cache.apk',
    );
    await tempFile.writeAsBytes(const <int>[1, 2, 3], flush: true);
    addTearDown(() async {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    });

    final digest = await AndroidApkUpdateCoordinator.sha256FileHex(tempFile);
    final downloader = _FakeDownloader(bytes: const <int>[1, 2, 3]);
    final installer = _FakeCachedInstaller(
      error: StateError('android_apk_install_not_started'),
    );
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: downloader,
      installer: installer,
    );
    final asset = AppUpdateAsset(
      name: 'SecondLoop-android-arm64-v8a.apk',
      downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
      sha256: digest,
    );

    await expectLater(
      () => coordinator.performUpdate(asset: asset, onProgress: (_) {}),
      throwsA(isA<AndroidApkUpdateException>()),
    );

    installer.error = null;
    await coordinator.performUpdate(asset: asset, onProgress: (_) {});

    expect(installer.installCalls, 2);
    expect(downloader.downloadCalls, 1);
  });

  test('replaces stale cached apk file when newer sha256 is verified',
      () async {
    final firstFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}android-update-cache-v1.apk',
    );
    final secondFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}android-update-cache-v2.apk',
    );
    await firstFile.writeAsBytes(const <int>[1, 2, 3], flush: true);
    await secondFile.writeAsBytes(const <int>[4, 5, 6], flush: true);
    addTearDown(() async {
      if (firstFile.existsSync()) {
        await firstFile.delete();
      }
      if (secondFile.existsSync()) {
        await secondFile.delete();
      }
    });

    final firstDigest =
        await AndroidApkUpdateCoordinator.sha256FileHex(firstFile);
    final secondDigest =
        await AndroidApkUpdateCoordinator.sha256FileHex(secondFile);
    final installer = _FakeCachedInstaller();
    final coordinator = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: const <int>[1, 2, 3]),
      installer: installer,
    );

    await coordinator.performUpdate(
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a-v1.apk',
        downloadUri: Uri.parse('https://cdn.example.com/app-v1.apk'),
        sha256: firstDigest,
      ),
      onProgress: (_) {},
    );

    final cachedV1Path = installer.lastPath;
    expect(cachedV1Path, isNotNull);
    expect(File(cachedV1Path!).existsSync(), isTrue);

    final coordinatorWithNewBytes = AndroidApkUpdateCoordinator(
      downloader: _FakeDownloader(bytes: const <int>[4, 5, 6]),
      installer: installer,
    );
    await coordinatorWithNewBytes.performUpdate(
      asset: AppUpdateAsset(
        name: 'SecondLoop-android-arm64-v8a-v2.apk',
        downloadUri: Uri.parse('https://cdn.example.com/app-v2.apk'),
        sha256: secondDigest,
      ),
      onProgress: (_) {},
    );

    expect(File(cachedV1Path).existsSync(), isFalse);
  });
}
