import 'audio_transcribe_whisper_model_prefs.dart';
import 'audio_transcribe_whisper_model_store_stub.dart'
    if (dart.library.io) 'audio_transcribe_whisper_model_store_io.dart' as impl;

const String kDefaultAudioTranscribeWhisperBaseUrl =
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

enum AudioWhisperModelEnsureStatus {
  unsupported,
  alreadyAvailable,
  downloaded,
}

final class AudioWhisperModelDownloadProgress {
  const AudioWhisperModelDownloadProgress({
    required this.model,
    required this.receivedBytes,
    required this.totalBytes,
    required this.attempt,
    required this.maxAttempts,
  });

  final String model;
  final int receivedBytes;
  final int? totalBytes;
  final int attempt;
  final int maxAttempts;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (receivedBytes <= 0) return 0;
    if (receivedBytes >= total) return 1;
    return receivedBytes / total;
  }
}

final class AudioWhisperModelEnsureResult {
  const AudioWhisperModelEnsureResult({
    required this.model,
    required this.status,
    required this.path,
  });

  final String model;
  final AudioWhisperModelEnsureStatus status;
  final String? path;
}

abstract class AudioTranscribeWhisperModelStore {
  bool get supportsRuntimeDownload;

  Future<bool> isModelAvailable({required String model});

  Future<AudioWhisperModelEnsureResult> ensureModelAvailable({
    required String model,
    void Function(AudioWhisperModelDownloadProgress progress)? onProgress,
  });
}

String audioTranscribeWhisperModelFilename(String model) {
  switch (normalizeAudioTranscribeWhisperModel(model)) {
    case 'tiny':
      return 'ggml-tiny.bin';
    case 'small':
      return 'ggml-small.bin';
    case 'medium':
      return 'ggml-medium.bin';
    case 'large-v3-turbo':
      return 'ggml-large-v3-turbo.bin';
    case 'large-v3':
      return 'ggml-large-v3.bin';
    case 'base':
      return 'ggml-base.bin';
    default:
      return 'ggml-base.bin';
  }
}

AudioTranscribeWhisperModelStore createAudioTranscribeWhisperModelStore({
  Future<String> Function()? appDirProvider,
  String? whisperBaseUrl,
}) {
  return impl.createAudioTranscribeWhisperModelStore(
    appDirProvider: appDirProvider,
    whisperBaseUrl: whisperBaseUrl,
  );
}
