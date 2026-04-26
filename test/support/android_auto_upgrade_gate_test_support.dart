import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/android/android_apk_installer.dart';
import 'package:secondloop/core/update/android/android_apk_update_coordinator.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

const fakeAndroidApkSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class AndroidAutoUpdateService extends AppUpdateService {
  AndroidAutoUpdateService({required this.result});

  AppUpdateCheckResult result;

  int applyPendingCalls = 0;
  int checkCalls = 0;

  @override
  Future<PendingUpdateStartupResult> applyPendingUpdateOnStartup() async {
    applyPendingCalls += 1;
    return const PendingUpdateStartupResult.noPendingUpdate();
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    checkCalls += 1;
    return result;
  }
}

class FakeReleaseNotesService extends ReleaseNotesService {
  FakeReleaseNotesService({required this.result});

  final ReleaseNotesFetchResult result;
  int fetchCalls = 0;

  @override
  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    fetchCalls += 1;
    return result;
  }
}

class ThrowingReleaseNotesService extends ReleaseNotesService {
  ThrowingReleaseNotesService({required this.error});

  final Object error;
  int fetchCalls = 0;

  @override
  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    fetchCalls += 1;
    throw error;
  }
}

class NoopAndroidApkDownloader implements AndroidApkDownloader {
  NoopAndroidApkDownloader({this.completer});

  final Completer<void>? completer;

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 50, totalBytes: 100));
    if (completer != null) {
      await completer!.future;
    }
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
    final file =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
    file.writeAsBytesSync(const <int>[1, 2, 3], flush: true);
    return file;
  }
}

class NoopAndroidApkInstaller implements AndroidApkInstaller {
  @override
  Future<void> installApk({required String apkPath}) async {}

  @override
  Future<bool?> canRequestPackageInstalls() async => null;
}

class FakeAndroidApkUpdateCoordinator extends AndroidApkUpdateCoordinator {
  FakeAndroidApkUpdateCoordinator({
    this.error,
    this.reuseVerifiedDownloads = false,
    this.canRequestPackageInstallsResult,
  }) : super(
          downloader: NoopAndroidApkDownloader(),
          installer: NoopAndroidApkInstaller(),
        );

  Object? error;
  final bool reuseVerifiedDownloads;
  bool? canRequestPackageInstallsResult;

  int performCalls = 0;
  int downloadCalls = 0;
  int permissionCheckCalls = 0;
  final Set<String> _verifiedSha256 = <String>{};

  @override
  Future<bool?> canRequestPackageInstalls() async {
    permissionCheckCalls += 1;
    return canRequestPackageInstallsResult;
  }

  @override
  Future<void> performUpdate({
    required AppUpdateAsset asset,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    performCalls += 1;
    final normalizedSha256 = asset.sha256?.trim().toLowerCase();
    final hasVerifiedCache = reuseVerifiedDownloads &&
        normalizedSha256 != null &&
        normalizedSha256.isNotEmpty &&
        _verifiedSha256.contains(normalizedSha256);
    if (!hasVerifiedCache) {
      downloadCalls += 1;
      onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 100, totalBytes: 100),
      );
      if (reuseVerifiedDownloads &&
          normalizedSha256 != null &&
          normalizedSha256.isNotEmpty) {
        _verifiedSha256.add(normalizedSha256);
      }
    } else {
      onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 1, totalBytes: 1),
      );
    }
    if (error != null) {
      throw error!;
    }
  }
}

Future<void> settleAndroidUpdateFlow(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pumpAndSettle();
}
