import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

class AndroidApkInstallerRequiresPermissionSettingsException
    implements Exception {
  const AndroidApkInstallerRequiresPermissionSettingsException();
}

class AndroidApkDownloadCancelToken {
  bool _cancelled = false;
  final Completer<void> _whenCancelled = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _whenCancelled.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_whenCancelled.isCompleted) {
      _whenCancelled.complete();
    }
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

  Future<bool?> canRequestPackageInstalls() async => null;
}

class HttpAndroidApkDownloader implements AndroidApkDownloader {
  HttpAndroidApkDownloader({HttpClient? httpClient})
      : _providedHttpClient = httpClient,
        _httpClient = httpClient ?? _createHttpClient();

  static const _connectionTimeout = Duration(seconds: 15);

  final HttpClient? _providedHttpClient;
  HttpClient _httpClient;

  static HttpClient _createHttpClient() {
    return HttpClient()..connectionTimeout = _connectionTimeout;
  }

  Future<void> dispose() async {
    if (_providedHttpClient == null) {
      _httpClient.close(force: true);
    }
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
    final request = await _awaitWithCancellation(
      _httpClient.getUrl(downloadUri),
      cancelToken,
      onCancel: _abortActiveClient,
    );
    final response = await _awaitWithCancellation(
      request.close(),
      cancelToken,
      onCancel: () {
        try {
          request.abort();
        } catch (_) {}
        _abortActiveClient();
      },
    );
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
    var sinkClosed = false;
    StreamIterator<List<int>>? responseIterator;
    try {
      responseIterator = StreamIterator<List<int>>(response);
      while (true) {
        final hasNextChunk = await _awaitWithCancellation(
          responseIterator.moveNext(),
          cancelToken,
          onCancel: () {
            unawaited(responseIterator?.cancel());
          },
        );
        if (!hasNextChunk) {
          break;
        }

        _throwIfCancelled(cancelToken);
        final chunk = responseIterator.current;
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
      sinkClosed = await discardPartialApkDownload(
        sink: sink,
        outputFile: outputFile,
      );
      rethrow;
    } finally {
      if (responseIterator != null) {
        try {
          await responseIterator.cancel();
        } catch (_) {}
      }
      if (!sinkClosed) {
        await sink.flush();
        await sink.close();
      }
    }

    return outputFile;
  }

  void _throwIfCancelled(AndroidApkDownloadCancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const AndroidApkDownloadCancelledException();
    }
  }

  Future<T> _awaitWithCancellation<T>(
    Future<T> future,
    AndroidApkDownloadCancelToken? cancelToken, {
    void Function()? onCancel,
  }) async {
    if (cancelToken == null) {
      return future;
    }
    return Future.any<T>([
      future,
      cancelToken.whenCancelled.then<T>((_) {
        onCancel?.call();
        throw const AndroidApkDownloadCancelledException();
      }),
    ]);
  }

  void _abortActiveClient() {
    if (_providedHttpClient != null) {
      return;
    }
    _httpClient.close(force: true);
    _httpClient = _createHttpClient();
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

@visibleForTesting
Future<bool> discardPartialApkDownload({
  required IOSink sink,
  required File outputFile,
}) async {
  var sinkClosed = false;
  await closeSinkBeforeDeleting(
    closeSink: () async {
      await sink.flush();
      await sink.close();
      sinkClosed = true;
    },
    deleteFile: () async {
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
    },
  );
  return sinkClosed;
}

@visibleForTesting
Future<void> closeSinkBeforeDeleting({
  required Future<void> Function() closeSink,
  required Future<void> Function() deleteFile,
}) async {
  try {
    await closeSink();
  } catch (_) {}
  try {
    await deleteFile();
  } catch (_) {}
}

class MethodChannelAndroidApkInstaller implements AndroidApkInstaller {
  MethodChannelAndroidApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('secondloop/android_update');

  final MethodChannel _channel;

  @override
  Future<void> installApk({required String apkPath}) async {
    final dynamic rawResult =
        await _channel.invokeMethod<Object?>('installApk', {
      'path': apkPath,
    });
    final result = _parseInstallResult(rawResult);
    switch (result) {
      case _AndroidApkInstallResult.launchedInstaller:
        return;
      case _AndroidApkInstallResult.permissionSettingsOpened:
        throw const AndroidApkInstallerRequiresPermissionSettingsException();
      case _AndroidApkInstallResult.failed:
        throw StateError('android_apk_install_not_started');
    }
  }

  @override
  Future<bool?> canRequestPackageInstalls() async {
    final dynamic rawResult =
        await _channel.invokeMethod<Object?>('canRequestPackageInstalls');
    if (rawResult is bool) {
      return rawResult;
    }
    if (rawResult == null) {
      return null;
    }
    throw StateError('android_apk_install_invalid_permission_result');
  }

  _AndroidApkInstallResult _parseInstallResult(dynamic rawResult) {
    if (rawResult == true) {
      return _AndroidApkInstallResult.launchedInstaller;
    }
    if (rawResult == false || rawResult == null) {
      return _AndroidApkInstallResult.failed;
    }
    if (rawResult is String) {
      return _AndroidApkInstallResult.fromChannelValue(rawResult);
    }
    if (rawResult is Map) {
      final status = rawResult['status'];
      if (status is String) {
        return _AndroidApkInstallResult.fromChannelValue(status);
      }
    }
    throw StateError('android_apk_install_invalid_result');
  }
}

enum _AndroidApkInstallResult {
  launchedInstaller('launched_installer'),
  permissionSettingsOpened('permission_settings_opened'),
  failed('failed');

  const _AndroidApkInstallResult(this.channelValue);

  final String channelValue;

  static _AndroidApkInstallResult fromChannelValue(String value) {
    final normalized = value.trim();
    for (final result in values) {
      if (result.channelValue == normalized) {
        return result;
      }
    }
    throw StateError('android_apk_install_unknown_status_$value');
  }
}
