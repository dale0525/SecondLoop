import '../../i18n/strings.g.dart';
import '../audio_transcribe/audio_transcribe_enqueue.dart';

typedef AttachmentAnnotationJobUiState = ({
  bool enabled,
  bool canRunNow,
  String setupRequiredLabel,
});

AttachmentAnnotationJobUiState resolveAttachmentAnnotationJobUiState({
  required String mimeType,
  required Translations t,
  required bool isZhLocale,
  required bool annotationEnabled,
  required bool annotationCanRunNow,
  required bool audioTranscribeEnabled,
  required bool audioTranscribeCanRunNow,
}) {
  if (isAudioTranscribeCandidateMimeType(mimeType)) {
    final title = t.settings.mediaAnnotation.audioTranscribe.title;
    return (
      enabled: audioTranscribeEnabled,
      canRunNow: audioTranscribeCanRunNow,
      setupRequiredLabel: isZhLocale ? '$title需要先配置' : '$title needs setup',
    );
  }

  return (
    enabled: annotationEnabled,
    canRunNow: annotationCanRunNow,
    setupRequiredLabel: t.chat.attachmentAnnotationNeedsSetup,
  );
}
