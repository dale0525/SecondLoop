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
  AndroidApkUpdateCoordinator({
    required AndroidApkDownloader downloader,
    required AndroidApkInstaller installer,
  })  : _downloader = downloader,
        _installer = installer;

  final AndroidApkDownloader _downloader;
  final AndroidApkInstaller _installer;
  final Map<String, _CachedDownloadedApk> _verifiedApkCache =
      <String, _CachedDownloadedApk>{};

  Future<void> performUpdate({
    required AppUpdateAsset asset,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    final expectedSha256 = asset.sha256?.trim();
    final cacheKey = _cacheKeyForAsset(expectedSha256);
    final cachedFile = cacheKey == null ? null : _resolveCachedFile(cacheKey);

    late final File downloadedFile;
    if (cachedFile != null) {
      downloadedFile = cachedFile;
      onProgress(
        const AndroidApkDownloadProgress(receivedBytes: 1, totalBytes: 1),
      );
    } else {
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
    }

    _throwIfCancelled(cancelToken);
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      try {
        final actualSha256 = await sha256FileHex(downloadedFile);
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          throw StateError('android_apk_sha256_mismatch');
        }
      } catch (error) {
        if (cancelToken?.isCancelled == true) {
          throw const AndroidApkDownloadCancelledException();
        }
        if (cacheKey != null) {
          _verifiedApkCache.remove(cacheKey);
        }
        await _deleteDownloadedFileIfPresent(downloadedFile);
        throw AndroidApkUpdateException(
          type: AndroidApkUpdateFailureType.integrityCheck,
          cause: error,
        );
      }
    }
    if (cacheKey != null) {
      _verifiedApkCache[cacheKey] = _CachedDownloadedApk(
        path: downloadedFile.path,
      );
    }

    _throwIfCancelled(cancelToken);
    try {
      await _installer.installApk(apkPath: downloadedFile.path);
    } on AndroidApkInstallerRequiresPermissionSettingsException {
      rethrow;
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

  void _throwIfCancelled(AndroidApkDownloadCancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
  }

  File? _resolveCachedFile(String cacheKey) {
    final cached = _verifiedApkCache[cacheKey];
    if (cached == null) return null;
    final file = File(cached.path);
    if (!file.existsSync()) {
      _verifiedApkCache.remove(cacheKey);
      return null;
    }
    return file;
  }

  Future<void> _deleteDownloadedFileIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String? _cacheKeyForAsset(String? expectedSha256) {
    final normalizedSha = expectedSha256?.trim().toLowerCase();
    if (normalizedSha != null && normalizedSha.isNotEmpty) {
      return 'sha256:$normalizedSha';
    }
    return null;
  }
}

class _CachedDownloadedApk {
  const _CachedDownloadedApk({required this.path});

  final String path;
}
