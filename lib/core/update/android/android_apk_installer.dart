import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AndroidApkDownloadProgress {
  const AndroidApkDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  bool get isIndeterminate => totalBytes <= 0;

  double? get fraction {
    if (isIndeterminate) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int? get percent {
    final value = fraction;
    if (value == null) return null;
    return (value * 100).round();
  }
}

typedef AndroidApkDownloadProgressCallback = void Function(
  AndroidApkDownloadProgress progress,
);

class AndroidApkDownloadCancelledException implements Exception {
  const AndroidApkDownloadCancelledException();
}

class AndroidApkDownloadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

abstract class AndroidApkDownloader {
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  });
}

abstract class AndroidApkInstaller {
  Future<void> installApk({required String apkPath});
}

class HttpAndroidApkDownloader implements AndroidApkDownloader {
  HttpAndroidApkDownloader({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<void> dispose() async {
    _httpClient.close(force: true);
  }

  @override
  Future<File> downloadApk({
    required Uri downloadUri,
    required String fileName,
    required AndroidApkDownloadProgressCallback onProgress,
    AndroidApkDownloadCancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updateDir =
        Directory('${tempDir.path}${Platform.pathSeparator}update_apks');
    await updateDir.create(recursive: true);

    final outputFile = File(
      '${updateDir.path}${Platform.pathSeparator}${_sanitizeApkFileName(fileName)}',
    );
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }

    _throwIfCancelled(cancelToken);
    final request = await _httpClient.getUrl(downloadUri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('apk_download_http_${response.statusCode}',
          uri: downloadUri);
    }

    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    onProgress(
      AndroidApkDownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
      ),
    );

    final sink = outputFile.openWrite();
    try {
      await for (final chunk in response) {
        _throwIfCancelled(cancelToken);
        receivedBytes += chunk.length;
        sink.add(chunk);
        onProgress(
          AndroidApkDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      _throwIfCancelled(cancelToken);
    } catch (_) {
      try {
        if (outputFile.existsSync()) {
          await outputFile.delete();
        }
      } catch (_) {}
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
    }

    return outputFile;
  }

  void _throwIfCancelled(AndroidApkDownloadCancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
  }

  static String _sanitizeApkFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
    if (sanitized.isEmpty) {
      return 'secondloop-update.apk';
    }
    if (sanitized.toLowerCase().endsWith('.apk')) {
      return sanitized;
    }
    return '$sanitized.apk';
  }
}

class MethodChannelAndroidApkInstaller implements AndroidApkInstaller {
  MethodChannelAndroidApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('secondloop/android_update');

  final MethodChannel _channel;

  @override
  Future<void> installApk({required String apkPath}) async {
    final launched = await _channel.invokeMethod<bool>('installApk', {
      'path': apkPath,
    });
    if (launched != true) {
      throw StateError('android_apk_install_not_started');
    }
  }
}
