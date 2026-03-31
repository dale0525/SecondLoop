import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../app_update_service.dart';
import 'android_apk_installer.dart';

enum AndroidApkUpdateFailureType {
  download,
  integrityCheck,
  installLaunch,
}

class AndroidApkUpdateException implements Exception {
  const AndroidApkUpdateException({
    required this.type,
    required this.cause,
  });

  final AndroidApkUpdateFailureType type;
  final Object cause;

  @override
  String toString() => 'AndroidApkUpdateException($type, $cause)';
}

class AndroidApkUpdateCoordinator {
  const AndroidApkUpdateCoordinator({
    required AndroidApkDownloader downloader,
    required AndroidApkInstaller installer,
  })  : _downloader = downloader,
        _installer = installer;

  final AndroidApkDownloader _downloader;
  final AndroidApkInstaller _installer;

  Future<void> performUpdate({
    required AppUpdateAsset asset,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    late final File downloadedFile;
    try {
      downloadedFile = await _downloader.downloadApk(
        downloadUri: asset.downloadUri,
        fileName: asset.name,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on AndroidApkDownloadCancelledException {
      rethrow;
    } catch (error) {
      throw AndroidApkUpdateException(
        type: AndroidApkUpdateFailureType.download,
        cause: error,
      );
    }

    final expectedSha256 = asset.sha256?.trim();
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      try {
        final actualSha256 = await sha256FileHex(downloadedFile);
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          throw StateError('android_apk_sha256_mismatch');
        }
      } catch (error) {
        throw AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.integrityCheck,
          cause: error,
        );
      }
    }

    try {
      await _installer.installApk(apkPath: downloadedFile.path);
    } catch (error) {
      throw AndroidApkUpdateException(
        type: AndroidApkUpdateFailureType.installLaunch,
        cause: error,
      );
    }
  }

  static Future<String> sha256FileHex(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    final buffer = StringBuffer();
    for (final byte in digest.bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
