import 'dart:async';
import 'dart:io';

import '../backend/native_app_dir.dart';
import 'audio_transcribe_whisper_model_prefs.dart';
import 'audio_transcribe_whisper_model_store.dart';

typedef AudioWhisperModelDownloadFile = Future<void> Function({
  required Uri url,
  required File destinationFile,
  required void Function(int receivedBytes, int? totalBytes) onProgress,
});

AudioTranscribeWhisperModelStore createAudioTranscribeWhisperModelStore({
  Future<String> Function()? appDirProvider,
  String? whisperBaseUrl,
}) {
  return FileSystemAudioTranscribeWhisperModelStore(
    appDirProvider: appDirProvider ?? getNativeAppDir,
    whisperBaseUrl: whisperBaseUrl ?? kDefaultAudioTranscribeWhisperBaseUrl,
  );
}

final class FileSystemAudioTranscribeWhisperModelStore
    implements AudioTranscribeWhisperModelStore {
  FileSystemAudioTranscribeWhisperModelStore({
    this.appDirProvider = getNativeAppDir,
    this.whisperBaseUrl = kDefaultAudioTranscribeWhisperBaseUrl,
    List<Duration>? retryDelays,
    AudioWhisperModelDownloadFile? downloadFile,
  })  : retryDelays = retryDelays ??
            const <Duration>[
              Duration.zero,
              Duration(milliseconds: 500),
              Duration(milliseconds: 1000),
            ],
        _downloadFile = downloadFile ?? _downloadFileDefault;

  final Future<String> Function() appDirProvider;
  final String whisperBaseUrl;
  final List<Duration> retryDelays;
  final AudioWhisperModelDownloadFile _downloadFile;

  @override
  bool get supportsRuntimeDownload {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Future<bool> isModelAvailable({required String model}) async {
    if (!supportsRuntimeDownload) return false;
    final file = await _resolveModelFile(model: model);
    return _isUsableModelFile(file);
  }

  @override
  Future<AudioWhisperModelEnsureResult> ensureModelAvailable({
    required String model,
    void Function(AudioWhisperModelDownloadProgress progress)? onProgress,
  }) async {
    final normalizedModel = normalizeAudioTranscribeWhisperModel(model);
    if (!supportsRuntimeDownload) {
      return AudioWhisperModelEnsureResult(
        model: normalizedModel,
        status: AudioWhisperModelEnsureStatus.unsupported,
        path: null,
      );
    }

    final targetFile = await _resolveModelFile(model: normalizedModel);
    if (await _isUsableModelFile(targetFile)) {
      return AudioWhisperModelEnsureResult(
        model: normalizedModel,
        status: AudioWhisperModelEnsureStatus.alreadyAvailable,
        path: targetFile.path,
      );
    }

    await targetFile.parent.create(recursive: true);
    final retries = retryDelays.isEmpty
        ? const <Duration>[Duration.zero]
        : List<Duration>.from(retryDelays, growable: false);
    final modelUrl = _buildModelUri(normalizedModel);

    Object? lastError;
    StackTrace? lastStack;
    for (var index = 0; index < retries.length; index += 1) {
      final delay = retries[index];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      final tempFile = File('${targetFile.path}.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final attempt = index + 1;
      try {
        await _downloadFile(
          url: modelUrl,
          destinationFile: tempFile,
          onProgress: (receivedBytes, totalBytes) {
            onProgress?.call(
              AudioWhisperModelDownloadProgress(
                model: normalizedModel,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                attempt: attempt,
                maxAttempts: retries.length,
              ),
            );
          },
        );

        int downloadedBytes;
        try {
          downloadedBytes = await tempFile.length();
        } catch (_) {
          downloadedBytes = 0;
        }
        if (downloadedBytes <= 0) {
          throw StateError('audio_whisper_model_download_empty');
        }

        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);

        onProgress?.call(
          AudioWhisperModelDownloadProgress(
            model: normalizedModel,
            receivedBytes: downloadedBytes,
            totalBytes: downloadedBytes,
            attempt: attempt,
            maxAttempts: retries.length,
          ),
        );

        return AudioWhisperModelEnsureResult(
          model: normalizedModel,
          status: AudioWhisperModelEnsureStatus.downloaded,
          path: targetFile.path,
        );
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    Error.throwWithStackTrace(
      StateError(
        'audio_whisper_model_download_failed:$normalizedModel:'
        '${lastError ?? 'unknown'}',
      ),
      lastStack ?? StackTrace.current,
    );
  }

  Uri _buildModelUri(String model) {
    final modelFile = audioTranscribeWhisperModelFilename(model);
    final baseUrl = whisperBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw StateError('audio_whisper_model_download_base_url_missing');
    }

    final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase/$modelFile');
  }

  Future<File> _resolveModelFile({required String model}) async {
    final appDir = (await appDirProvider()).trim();
    if (appDir.isEmpty) {
      throw StateError('audio_whisper_model_download_app_dir_missing');
    }

    final modelFile = audioTranscribeWhisperModelFilename(model);
    return File('$appDir/ocr/desktop/runtime/whisper/$modelFile');
  }

  static Future<bool> _isUsableModelFile(File file) async {
    try {
      if (!await file.exists()) return false;
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _downloadFileDefault({
    required Uri url,
    required File destinationFile,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;

    try {
      final request =
          await client.getUrl(url).timeout(const Duration(seconds: 20));
      final response =
          await request.close().timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body =
            await response.transform(const SystemEncoding().decoder).join();
        throw HttpException(
          'download failed (${response.statusCode}): ${body.trim()}',
          uri: url,
        );
      }

      await destinationFile.parent.create(recursive: true);
      sink = destinationFile.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      final total = response.contentLength >= 0 ? response.contentLength : null;

      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }

      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }
}
