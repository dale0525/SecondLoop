import 'audio_transcribe_whisper_model_prefs.dart';
import 'audio_transcribe_whisper_model_store.dart';

AudioTranscribeWhisperModelStore createAudioTranscribeWhisperModelStore({
  Future<String> Function()? appDirProvider,
  String? whisperBaseUrl,
}) {
  return const _UnsupportedAudioTranscribeWhisperModelStore();
}

final class _UnsupportedAudioTranscribeWhisperModelStore
    implements AudioTranscribeWhisperModelStore {
  const _UnsupportedAudioTranscribeWhisperModelStore();

  @override
  bool get supportsRuntimeDownload => false;

  @override
  Future<bool> isModelAvailable({required String model}) async {
    return false;
  }

  @override
  Future<AudioWhisperModelEnsureResult> ensureModelAvailable({
    required String model,
    void Function(AudioWhisperModelDownloadProgress progress)? onProgress,
  }) async {
    final normalized = normalizeAudioTranscribeWhisperModel(model);
    return AudioWhisperModelEnsureResult(
      model: normalized,
      status: AudioWhisperModelEnsureStatus.unsupported,
      path: null,
    );
  }
}
